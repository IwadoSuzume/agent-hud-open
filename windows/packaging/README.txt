Agent HUD Open for Windows — portable package

This is the community Windows port of Agent HUD Open (https://github.com/jazzenchen/agent-hud-open), built from the
fork's windows-port branch. It is not an official release of the project, and it is not signed.

What it needs
- Windows 10 22H2 or Windows 11, x64.
- The .NET 10 Desktop Runtime (x64). If it is missing, AgentHUD.exe says so and offers Microsoft's download page.
- The Microsoft Visual C++ Redistributable (x64), which most machines already have. If it is missing, Agent HUD says
  "A library it needs was not found" and names Microsoft's download page:
  https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist

Running it
- Unpack the folder somewhere it can stay (for example under your user folder), then start AgentHUD.exe.
- AgentHUD.exe --demo shows example data without reading any client.
- The clients' hooks and any MCP server you added run agenthud-engine.exe from this folder. Before you move the folder
  or unpack a newer version elsewhere, turn off Settings > Client hooks (it removes the hook entries Agent HUD added),
  then turn it on again from the new place. An MCP entry you added yourself stays until you remove it with the
  client's own command (for example `claude mcp remove`); add it again with the new path.
- Launch at login follows the copy you run: starting a copy from another folder points the entry at that copy, and an
  entry you disabled in Task Manager stays disabled.

Removing it
1. In Settings, turn off Client hooks (this removes the hook entries Agent HUD added to the clients' settings) and
   Launch at login. Remove an MCP entry you added with the client's own command.
2. Quit Agent HUD from its tray icon and delete this folder.
3. Agent HUD's own settings and usage history are in %APPDATA%\Agent HUD Open, and its instance lock in
   %LOCALAPPDATA%\app.agenthud; delete both folders too if you want nothing left.

Files
- AgentHUD.exe and its .dll files: the Windows shell (tray icon, HUD, settings and statistics windows).
- agenthud-engine.exe: the engine (usage, sessions, approvals, client hooks, --mcp), with the Swift runtime libraries
  beside it.
- LICENSE.txt: Agent HUD's licence (Apache License 2.0).
- THIRD_PARTY_NOTICES.txt: notices for the code Agent HUD adapts.
- RUNTIME_NOTICES.txt: notices for the Swift runtime libraries in this folder.
- agenthud-package.json: the package's version and source commit; Launch at login works only in a folder that has it.
