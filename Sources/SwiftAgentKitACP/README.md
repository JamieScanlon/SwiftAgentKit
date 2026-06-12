# SwiftAgentKitACP

Swift implementation of the [Agent Client Protocol (ACP)](https://agentclientprotocol.com) for SwiftAgentKit.

## Quick Start

```swift
import SwiftAgentKit
import SwiftAgentKitACP

SwiftAgentKitLogging.bootstrap()

// Connect to an ACP agent subprocess
let client = try await ACPClient.boot(
    name: "my-agent",
    command: "my-acp-agent",
    arguments: []
)

let text = try await client.promptCollectingText("Analyze this project")
print(text)

await client.shutdown()
```

See [docs/ACP.md](../../docs/ACP.md) and [docs/ACPImplementation.md](../../docs/ACPImplementation.md) for full documentation.
