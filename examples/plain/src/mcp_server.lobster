// The smallest game side of Creel's MCP (src/mcp/serve.lobster, mcp/README.md): the hooks it asks for. This example
// has no data to start a match from, so start says so; a game starts its match here, steps it its way, and saves it.
// mcp/test/test.js drives it through mcp/creel-mcp.js.
import sim_modules
import mcp.serve

def mcp_start(args:JV) -> string: return "examples/plain has no data to start a match from (a game\'s mcp_start does)"

def mcp_step(): step()

def mcp_save(path:string) -> string: return "examples/plain has no saves"

def mcp_load(path:string) -> string: return "examples/plain has no saves"

mcp_serve()
