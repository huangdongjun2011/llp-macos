import PackagePlugin

@main
struct ValidatedOpenAPIGenerator: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let contract = context.package.directory.appending("../common/apis/llp-apis.yaml")
        let config = target.directory.appending("openapi-generator-config.yaml")
        let output = context.pluginWorkDirectory
        let generator = try context.tool(named: "swift-openapi-generator").path
        return [.buildCommand(
            displayName: "Generate Swift OpenAPI client",
            executable: generator,
            arguments: ["generate", contract.string, "--config", config.string, "--output-directory", output.string],
            inputFiles: [contract, config],
            outputFiles: [output.appending("Types.swift"), output.appending("Client.swift")]
        )]
    }
}
