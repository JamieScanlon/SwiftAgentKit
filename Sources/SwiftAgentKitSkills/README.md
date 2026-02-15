# SwiftAgentKitSkills

Add-on library for the [Agent Skills specification](https://agentskills.io/specification). Provides parsing and loading of skills from directories containing `SKILL.md` files with YAML frontmatter.

## Overview

A skill is a directory containing at minimum a `SKILL.md` file:

```
skill-name/
└── SKILL.md          # Required
```

Optional directories: `scripts/`, `references/`, `assets/`

## SKILL.md Format

```yaml
---
name: pdf-processing
description: Extract text and tables from PDF files, fill forms, merge documents.
license: Apache-2.0
metadata:
  author: example-org
  version: "1.0"
---
```

Followed by Markdown body content (skill instructions).

## Usage

```swift
import SwiftAgentKitSkills

// Parse a single skill
let parser = SkillParser()
let skill = try parser.parse(directoryURL: URL(fileURLWithPath: "./my-skill"))

// Load all skills from a directory
let skillsDirectory = URL(fileURLWithPath: "./skills")
let loader = SkillLoader(skillsDirectoryURL: skillsDirectory)
let skills = try loader.loadSkills()

// Load metadata only (for progressive disclosure)
let metadata = try loader.loadMetadata()
```

## Injecting Skills into the System Prompt

Use `SkillLoader.loadMetadata()` to get a lightweight index of available skills, then format it for injection into your LLM system prompt. This lets the agent know which skills exist and when to use them, without loading full instructions until a skill is activated.

`SkillPromptFormatter` supports three output formats: `formatAsXML`, `formatAsYAML`, and `formatAsJSON`.

### XML Format

Format skill metadata as XML for inclusion in the system prompt:

```swift
import SwiftAgentKitSkills

let skillsDirectory = URL(fileURLWithPath: "/path/to/skills")
let loader = SkillLoader(skillsDirectoryURL: skillsDirectory)
let metadata = try loader.loadMetadata()

let availableSkillsXML = SkillPromptFormatter.formatAsXML(metadata)
// Inject availableSkillsXML into your system prompt
```

This produces:

```xml
<available_skills>
  <skill>
    <name>pdf-processing</name>
    <description>Extracts text and tables from PDF files, fills forms, merges documents.</description>
    <location>/path/to/skills/pdf-processing/SKILL.md</location>
  </skill>
  <skill>
    <name>data-analysis</name>
    <description>Analyzes datasets, generates charts, and creates summary reports.</description>
    <location>/path/to/skills/data-analysis/SKILL.md</location>
  </skill>
</available_skills>
```

### YAML and JSON Formats

```swift
let yaml = SkillPromptFormatter.formatAsYAML(metadata)
let json = SkillPromptFormatter.formatAsJSON(metadata)
```

YAML output:
```yaml
available_skills:
- name: pdf-processing
  description: Extracts text and tables from PDF files...
  location: /path/to/skills/pdf-processing/SKILL.md
```

JSON output:
```json
{"available_skills":[{"name":"pdf-processing","description":"...","location":"/path/to/skills/pdf-processing/SKILL.md"}]}
```

### Full Integration Example

```swift
// 1. At startup: load metadata and inject into system prompt
let skillsDirectory = URL(fileURLWithPath: "/path/to/skills")
let loader = SkillLoader(skillsDirectoryURL: skillsDirectory)
let metadata = try loader.loadMetadata()
let skillsSection = SkillPromptFormatter.formatAsXML(metadata)

let systemPrompt = """
You are a helpful assistant with access to the following skills.
When the user's task matches a skill, activate it by loading the full instructions.

\(skillsSection)

To use a skill, read its SKILL.md file at the location given above.
"""

// 2. When the agent decides to activate a skill (e.g., based on user intent):
let skill = try loader.loadSkill(named: "pdf-processing")
if let skill {
    // Append full instructions to context
    let instructions = skill.fullInstructions
    // Send to LLM as additional context...
}
```

### Custom Formatting

If you need a different format than XML, YAML, or JSON:

```swift
for m in metadata {
    print("\(m.name): \(m.description) -> \(m.skillFileURL.path)")
}
```

## Activation Tracking

`SkillLoader` tracks which skills have been "activated" (fully loaded into context). Call `activate(_:)` after injecting a skill's instructions into your agent, and `deactivateSkill(named:)` when removing it.

```swift
// Load and activate
let skill = try loader.loadSkill(named: "pdf-processing")
if let skill {
    // Inject skill.fullInstructions into context...
    await loader.activate(skill)
}

// Or use the convenience method
let skill = try loader.loadAndActivateSkill(named: "pdf-processing")

// Query activated skills
let active = await loader.activatedSkills  // Set<String>
await loader.isActivated(name: "pdf-processing")  // Bool

// Deactivate when removing from context
await loader.deactivateSkill(named: "pdf-processing")
await loader.deactivateAllSkills()
```

## SkillsToolProvider

`SkillsToolProvider` implements `ToolProvider` so the LLM can activate and deactivate skills via tool calls. Add it alongside other tool providers (MCP, A2A) when using `ToolAwareAdapter` or `Orchestrator`.

**Tools exposed:**
- `agent-skill-activate(skill_name: "...")` — Loads a skill, marks it activated, and returns full instructions for context injection
- `agent-skill-deactivate(skill_name: "...")` — Removes a skill from the activated set
- `agent-skills-list-active()` — Returns names of currently activated skills

```swift
import SwiftAgentKitSkills
import SwiftAgentKitAdapters

let skillsDirectory = URL(fileURLWithPath: "/path/to/skills")
let loader = SkillLoader(skillsDirectoryURL: skillsDirectory)
let skillsProvider = SkillsToolProvider(
    loader: loader,
    onSkillActivated: { skill in
        // Inject skill.fullInstructions into system context
    },
    onSkillDeactivated: { skillName in
        // Remove skill instructions from system context
    }
)

// Add to adapter's tool providers
let adapter = try AdapterBuilder()
    .withToolProvider(skillsProvider)
    // ... other providers
    .build()
```

The `onSkillActivated` callback receives the loaded `Skill` (use `skill.fullInstructions` to inject). The `onSkillDeactivated` callback receives the skill name for removal. Updating system context is beyond this library's scope; use these callbacks to integrate.

## Progressive Disclosure

Per the spec, skills should be structured for efficient context use:

1. **Metadata** (~100 tokens): Load `name` and `description` at startup for all skills
2. **Instructions** (< 5000 tokens): Load full `SKILL.md` body when skill is activated
3. **Resources** (as needed): Load `scripts/`, `references/`, `assets/` on demand

Use `loadMetadata()` for indexing, then `loadSkill(named:)` when activating a skill.
