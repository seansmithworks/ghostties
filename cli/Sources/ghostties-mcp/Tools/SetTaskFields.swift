import Foundation
import GhosttiesCore

private let allowedKeys: Set<String> = ["worktree", "pr", "pr-state", "pr-url", "branch"]

func setTaskFieldsTool() -> Tool {
    Tool(
        name: "set_task_fields",
        description: "Write worktree/PR metadata back to a task file after an agent creates a PR. Allowed keys: worktree, pr, pr-state, pr-url, branch.",
        inputSchema: S.object(
            properties: [
                ("taskId", S.string("Task id or unambiguous prefix.")),
                ("fields", .object([
                    "type": .string("object"),
                    "description": .string("Fields to update. Allowed keys: worktree, pr, pr-state, pr-url, branch."),
                    "properties": .object([
                        "worktree":  .object(["type": .string("string"), "description": .string("Absolute path to the git worktree for this task.")]),
                        "pr":        .object(["type": .string("string"), "description": .string("PR number (as string).")]),
                        "pr-state":  .object(["type": .string("string"), "description": .string("PR state (e.g. open, merged, closed).")]),
                        "pr-url":    .object(["type": .string("string"), "description": .string("Full URL of the pull request.")]),
                        "branch":    .object(["type": .string("string"), "description": .string("Branch name associated with this task.")])
                    ]),
                    "additionalProperties": .bool(false)
                ]))
            ],
            required: ["taskId", "fields"]
        ),
        handler: { args, resolver in
            guard let taskIdArg = args["taskId"]?.string, !taskIdArg.isEmpty else {
                return .error("missing required argument: taskId")
            }
            guard case .object(let fieldsObj) = args["fields"] else {
                return .error("missing required argument: fields")
            }
            if fieldsObj.isEmpty {
                return .error("fields must contain at least one key to update")
            }

            // Validate all keys before writing anything.
            let unknownKeys = fieldsObj.keys.filter { !allowedKeys.contains($0) }
            if !unknownKeys.isEmpty {
                let sorted = unknownKeys.sorted().joined(separator: ", ")
                let allowed = allowedKeys.sorted().joined(separator: ", ")
                return .error("unknown field key(s): \(sorted). Allowed keys are: \(allowed)")
            }

            let dir: URL
            do { dir = try resolver.resolve() }
            catch { return .error(error.localizedDescription) }

            let store = TaskStore(directory: dir)
            do {
                let (task, url) = try store.resolve(idOrPrefix: taskIdArg)

                var pairs = task.frontmatter
                var updatedKeys: [String] = []
                for key in fieldsObj.keys.sorted() {
                    if let val = fieldsObj[key]?.string {
                        pairs = Frontmatter.set(key, val, in: pairs)
                        updatedKeys.append(key)
                    }
                }
                let now = isoTimestamp()
                pairs = Frontmatter.set("updated", now, in: pairs)

                try store.write(pairs: pairs, body: task.body, to: url)
                Log.info("set_task_fields: updated \(updatedKeys.joined(separator: ", ")) on \(task.id)")

                return .json(.object([
                    "success": .bool(true),
                    "taskId": .string(task.id),
                    "updatedFields": .array(updatedKeys.map(JSONValue.string))
                ]))
            } catch let err as CLIError {
                return .error(err.errorDescription ?? "set_task_fields failed")
            } catch {
                return .error(error.localizedDescription)
            }
        }
    )
}
