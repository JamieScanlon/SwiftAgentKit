# SwiftAgentKitSkills Module

The `SwiftAgentKitSkills` module implements support for the [Agent Skills specification](https://agentskills.io/specification). It provides parsing, loading, and integration of skills—reusable instruction packages for AI agents—from directories containing `SKILL.md` files with YAML frontmatter.

## Overview

Skills let you extend agent capabilities with modular, discoverable instruction sets. Each skill is a directory with a `SKILL.md` file that describes the skill and contains instructions the agent can load on demand. SwiftAgentKitSkills supports:

- **Skill discovery** — Load metadata for all skills at startup for agent awareness
- **Progressive disclosure** — Load full instructions only when a skill is activated (saves context tokens)
- **Tool integration** — Expose skill activation/deactivation as tools via `SkillsToolProvider`
- **Activation tracking** — Track which skills are currently loaded into context

## Installation

Add the `SwiftAgentKitSkills` dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/JamieScanlon/SwiftAgentKit.git", from: "0.1.3")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SwiftAgentKitSkills", package: "SwiftAgentKit"),
            // Also add SwiftAgentKitAdapters if using SkillsToolProvider with adapters
            .product(name: "SwiftAgentKitAdapters", package: "SwiftAgentKit")
        ]
    )
]
```

## Skill Structure

A skill is a directory containing at minimum a `SKILL.md` file:

```
skills/
├── pdf-processing/
│   └── SKILL.md          # Required
├── data-analysis/
│   ├── SKILL.md
│   ├── scripts/          # Optional
│   ├── references/       # Optional
│   └── assets/           # Optional
```

### SKILL.md Format

Each `SKILL.md` file has YAML frontmatter followed by Markdown body content:

```yaml
---
name: pdf-processing
description: Extract text and tables from PDF files, fill forms, merge documents.
license: Apache-2.0
metadata:
  author: example-org
  version: "1.0"
---

# PDF Processing Instructions

## When to Use
Activate this skill when the user needs to work with PDF files...

## Steps
1. Identify the type of PDF operation requested
2. Use the appropriate tool for extraction or manipulation
3. Return results in the requested format
```

**Frontmatter fields:**
- `name` (required) — Skill identifier, 1–64 chars, lowercase alphanumeric and hyphens. Must match directory name.
- `description` (required) — What the skill does and when to use it, max 1024 chars.
- `license` (optional) — License name or path to license file.
- `compatibility` (optional) — Environment requirements, max 500 chars.
- `metadata` (optional) — Arbitrary key-value pairs.
- `allowed-tools` (optional, experimental) — Space-delimited list of pre-approved tools.

## Basic Usage

### Parsing a Single Skill

```swift
import SwiftAgentKitSkills

let parser = SkillParser()
let skill = try parser.parse(directoryURL: URL(fileURLWithPath: "./my-skill"))

print("Skill: \(skill.name)")
print("Description: \(skill.description)")
print("Instructions: \(skill.fullInstructions)")
```

### Loading All Skills from a Directory

```swift
let skillsDirectory = URL(fileURLWithPath: "./skills")
let loader = SkillLoader(skillsDirectoryURL: skillsDirectory)

// Load full skills (including body content)
let skills = try loader.loadSkills()

for skill in skills {
    print("\(skill.name): \(skill.description)")
}
```

### Loading Metadata Only (Progressive Disclosure)

For efficient context use, load metadata at startup (~100 tokens per skill) and full instructions only when activating:

```swift
let loader = SkillLoader(skillsDirectoryURL: skillsDirectory)
let metadata = try loader.loadMetadata()

// metadata is [SkillMetadata] with name, description, directoryURL, skillFileURL
for m in metadata {
    print("\(m.name): \(m.description) -> \(m.skillFileURL.path)")
}
```

### Loading and Activating a Skill

```swift
// Load a skill by name (directory name must match)
if let skill = try loader.loadSkill(named: "pdf-processing") {
    // Inject skill.fullInstructions into your agent's context
    let instructions = skill.fullInstructions
    
    // Mark as activated so you can track it
    await loader.activate(skill)
}

// Or use the convenience method
if let skill = try loader.loadAndActivateSkill(named: "pdf-processing") {
    // Skill is loaded and activated; use skill.fullInstructions
}
```

## Injecting Skills into the System Prompt

Use `SkillPromptFormatter` to format skill metadata for inclusion in your LLM system prompt. The agent learns which skills exist without loading full instructions until needed.

### XML Format

```swift
let metadata = try loader.loadMetadata()
let availableSkillsXML = SkillPromptFormatter.formatAsXML(metadata)
```

Produces:

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

### Complete System Prompt Integration Example

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

To use a skill, call the agent-skill-activate tool with the skill name.
"""

// 2. When the agent activates a skill (via tool call or your logic):
if let skill = try loader.loadSkill(named: "pdf-processing") {
    let instructions = skill.fullInstructions
    await loader.activate(skill)
    // Append instructions to context and continue the conversation
}
```

## Activation Tracking

Track which skills are loaded into context:

```swift
// Activate after loading
let skill = try loader.loadSkill(named: "pdf-processing")
if let skill {
    await loader.activate(skill)
}

// Query activated skills
let active = await loader.activatedSkills  // Set<String>
let isActive = await loader.isActivated(name: "pdf-processing")  // Bool

// Deactivate when removing from context
await loader.deactivateSkill(named: "pdf-processing")
await loader.deactivateAllSkills()
```

## SkillsToolProvider: Tool-Based Skill Control

`SkillsToolProvider` implements `ToolProvider`, exposing skill activation and deactivation as tools. Add it to your adapter or orchestrator so the LLM can activate skills via tool calls.

**Exposed tools:**
- `agent-skill-activate` — Loads a skill, marks it activated, returns full instructions. Parameter: `skill_name`.
- `agent-skill-deactivate` — Removes a skill from the activated set. Parameter: `skill_name`.
- `agent-skills-list-active` — Returns names of currently activated skills. No parameters.

### Integration with AdapterBuilder

```swift
import SwiftAgentKitSkills
import SwiftAgentKitAdapters

let skillsDirectory = URL(fileURLWithPath: "/path/to/skills")
let loader = SkillLoader(skillsDirectoryURL: skillsDirectory)

// Callbacks for updating system context (you implement this)
var activeInstructions: [String] = []

let skillsProvider = SkillsToolProvider(
    loader: loader,
    onSkillActivated: { skill in
        // Add skill.fullInstructions to your system context
        await MainActor.run {
            activeInstructions.append(skill.fullInstructions)
        }
    },
    onSkillDeactivated: { skillName in
        // Remove skill instructions from system context
        await MainActor.run {
            activeInstructions.removeAll { $0.contains(skillName) }
        }
    }
)

let adapter = try AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "your-key"))
    .withToolProvider(skillsProvider)
    .build()
```

### Integration with Orchestrator

```swift
import SwiftAgentKitOrchestrator
import SwiftAgentKitSkills

let loader = SkillLoader(skillsDirectoryURL: skillsURL)
let skillsProvider = SkillsToolProvider(
    loader: loader,
    onSkillActivated: { skill in
        // Update orchestrator's dynamic context with skill instructions
    },
    onSkillDeactivated: { _ in }
)

let orchestrator = OrchestratorBuilder()
    .withLLM(adapter)
    .withToolProvider(skillsProvider)
    .build()
```

## Working with the Skill Model

The `Skill` struct provides additional helpers:

```swift
// Convenience accessors
skill.name           // From frontmatter
skill.description    // From frontmatter
skill.fullInstructions  // Description + body, suitable for context injection
skill.body           // Raw Markdown body
skill.directoryURL   // Skill root directory
skill.skillFileURL   // Path to SKILL.md

// Resolve relative paths within the skill (e.g., references, scripts)
if let refURL = skill.url(forRelativePath: "references/REFERENCE.md") {
    let content = try String(contentsOf: refURL)
}

// Check for optional directories
skill.hasScriptsDirectory
skill.hasReferencesDirectory
skill.hasAssetsDirectory
```

## Progressive Disclosure Best Practices

Per the Agent Skills spec, structure your usage for efficient context:

1. **Metadata** (~100 tokens) — Load `name` and `description` at startup for all skills via `loadMetadata()`.
2. **Instructions** (< 5000 tokens) — Load full `SKILL.md` body when activating via `loadSkill(named:)`.
3. **Resources** (as needed) — Load `scripts/`, `references/`, `assets/` on demand using `skill.url(forRelativePath:)`.

## Error Handling

```swift
do {
    let skill = try parser.parse(directoryURL: skillURL)
    // Use skill
} catch SkillParseError.fileNotFound(let url) {
    print("Skill file not found: \(url)")
} catch SkillParseError.invalidFrontmatterYAML(let url, let underlying) {
    print("Invalid YAML in \(url): \(underlying)")
} catch SkillParseError.missingRequiredField(let field) {
    print("Missing required field: \(field)")
} catch SkillParseError.invalidName(let name) {
    print("Invalid skill name: \(name)")
} catch SkillParseError.nameMismatch(let dir, let frontmatter) {
    print("Directory name '\(dir)' doesn't match frontmatter name '\(frontmatter)'")
}
```

## Example: End-to-End Skills Flow

```swift
import SwiftAgentKitSkills
import SwiftAgentKitAdapters

// Setup
let skillsDir = URL(fileURLWithPath: "./skills")
let loader = SkillLoader(skillsDirectoryURL: skillsDir)

// 1. Build system prompt with available skills
let metadata = try loader.loadMetadata()
let skillsXML = SkillPromptFormatter.formatAsXML(metadata)
let systemPrompt = """
You are an assistant with these skills. Activate a skill when the task matches.

\(skillsXML)

Use agent-skill-activate to load a skill's full instructions.
"""

// 2. Create adapter with SkillsToolProvider
var systemContext = systemPrompt
let skillsProvider = SkillsToolProvider(
    loader: loader,
    onSkillActivated: { skill in
        systemContext += "\n\n---\n\n\(skill.fullInstructions)"
    },
    onSkillDeactivated: { _ in
        // Simplified: in practice, remove only that skill's instructions
    }
)

let adapter = try AdapterBuilder()
    .withLLM(OpenAIAdapter(apiKey: "key", systemPrompt: DynamicPrompt(template: systemPrompt)))
    .withToolProvider(skillsProvider)
    .build()

// 3. Agent uses tools to activate skills as needed; callbacks update context
```
