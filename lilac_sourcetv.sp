#include <sourcemod>

// We only care about these detections,
// 	since they don't cause instant bans.
#define CHEAT_AIMBOT 	5
#define CHEAT_AIMLOCK 	6

#define INDEX_AIMBOT 	0
#define INDEX_AIMLOCK 	1
#define INDEX_MAX 	2

#define CVAR_ENABLE 	0
#define CVAR_STV_JOIN 	1
#define CVAR_LOG 	2
#define CVAR_RATE 	3
#define CVAR_MAX 	4

Handle cvar[CVAR_MAX];
int icvar[CVAR_MAX];

int playerinfo_detections[MAXPLAYERS + 1][INDEX_MAX];
bool playerinfo_recording[MAXPLAYERS + 1];

bool stv_restarted_map = false;
bool stv_recording = false;
char stv_demo_name[128];

char line[512];


public Plugin:myinfo = {
	name = "[Lilac] Auto SourceTV Recorder",
	author = "J_Tanzanite",
	description = "Automatically records SourceTV demos upon cheater detection.",
	version = "1.0.0-RC 1",
	url = ""
};


public void OnPluginStart()
{
	Handle tcvar;

	cvar[CVAR_ENABLE] = CreateConVar("lilac_stv_enable", "1",
		"Enable SourceTV auto recording.",
		FCVAR_PROTECTED, true, 0.0, true, 1.0);
	cvar[CVAR_STV_JOIN] = CreateConVar("lilac_stv_autojoin", "1",
		"Automatically restart map if SourceTV bot hasn't joined.",
		FCVAR_PROTECTED, true, 0.0, true, 1.0);
	cvar[CVAR_LOG] = CreateConVar("lilac_stv_log", "1",
		"Log recording info to addons/sourcemod/logs/lilac_stv.log",
		FCVAR_PROTECTED, true, 0.0, true, 1.0);
	cvar[CVAR_RATE] = CreateConVar("lilac_stv_tickrate", "1",
		"Automatically set SourceTV demo tickrate to the highest value possible for best quality recordings.",
		FCVAR_PROTECTED, true, 0.0, true, 1.0);

	for (int i = 0; i < CVAR_MAX; i++) {
		icvar[i] = GetConVarInt(cvar[i]);
		HookConVarChange(cvar[i], cvar_change);
	}

	// SourceTV must be enabled.
	if ((tcvar = FindConVar("tv_enable")) == null) {
		ThrowError("[Lilac SourceTV] ERROR: ConVar \"tv_enable\" not found!");
	}
	else {
		SetConVarInt(tcvar, 1, false, false);
		HookConVarChange(tcvar, cvar_lock);
	}

	// Block auto-recording.
	if ((tcvar = FindConVar("tv_autorecord")) == null) {
		ThrowError("[Lilac SourceTV] ERROR: ConVar \"tv_autorecord\" not found!");
	}
	else {
		if (GetConVarInt(tcvar))
			ServerCommand("tv_stoprecord");

		SetConVarInt(tcvar, 0, false, false);
		HookConVarChange(tcvar, cvar_lock);
	}

	// Set the value to server tickrate,
	// 	but DON'T block server owners from changing it.
	if (icvar[CVAR_RATE] && icvar[CVAR_ENABLE])
		ServerCommand("tv_snapshotrate %d", RoundToCeil(1.0 / GetTickInterval()));

	stv_restarted_map = false;
}

public void OnPluginEnd()
{
	ServerCommand("tv_stoprecord");
	stv_recording = false;
}

public void OnMapStart()
{
	// Reset all player upon a new map start.
	for (int i = 1; i <= MaxClients; i++) {
		playerinfo_recording[i] = false;

		for (int k = 0; k < INDEX_MAX; k++)
			playerinfo_detections[i][k] = 0;
	}

	if (stv_restarted_map == false)
		CreateTimer(10.0, timer_restart_map);

	// Not needed, but just in case.
	ServerCommand("tv_stoprecord");
	stv_recording = false;
}

public void OnMapEnd()
{
	ServerCommand("tv_stoprecord");
	stv_recording = false;
}

// This just feels wrong...
public void cvar_lock(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char cvarname[64];

	if (!icvar[CVAR_ENABLE])
		return;

	GetConVarName(convar, cvarname, sizeof(cvarname));
	if (StrEqual(cvarname, "tv_enable", false)) {
		if (StringToInt(newValue, 10) >= 1)
			return;

		ServerCommand("tv_enable 1");
	}
	else {
		if (StringToInt(newValue, 10) == 0)
			return;

		ServerCommand("tv_autorecord 0");
	}

	PrintToServer("[Lilac SourceTV] Blocked ConVar change \"%s\" to \"%s\".", cvarname, newValue);
}

public void cvar_change(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (view_as<Handle>(convar) == cvar[CVAR_ENABLE])
		icvar[CVAR_ENABLE] = StringToInt(newValue, 10);
	else if (view_as<Handle>(convar) == cvar[CVAR_STV_JOIN])
		icvar[CVAR_STV_JOIN] = StringToInt(newValue, 10);
	else if (view_as<Handle>(convar) == cvar[CVAR_LOG])
		icvar[CVAR_LOG] = StringToInt(newValue, 10);
	else if (view_as<Handle>(convar) == cvar[CVAR_RATE])
		icvar[CVAR_RATE] = StringToInt(newValue, 10);
}

public void OnClientConnected(int client)
{
	for (int i = 0; i < INDEX_MAX; i++)
		playerinfo_detections[client][i] = 0;

	playerinfo_recording[client] = false;
}

public void OnClientDisconnect(int client)
{
	update_recording_list(client, false);
}

public Action lilac_cheater_detected(int client, int cheat)
{
	if (!icvar[CVAR_ENABLE] || !is_player_valid(client))
		return;

	switch (cheat) {
	case CHEAT_AIMBOT: {
		CreateTimer(610.0, timer_decrement_aimbot, GetClientUserId(client));

		if (++playerinfo_detections[client][INDEX_AIMBOT] < 2)
			return;
	}
	case CHEAT_AIMLOCK: {
		CreateTimer(610.0, timer_decrement_aimlock, GetClientUserId(client));

		if (++playerinfo_detections[client][INDEX_AIMLOCK] < 2)
			return;
	}
	default: return;
	}

	update_recording_list(client, true);
}

void update_recording_list(int client, bool status)
{
	int players = 0;
	bool prevstatus;

	if (!icvar[CVAR_ENABLE])
		return;

	prevstatus = playerinfo_recording[client];
	playerinfo_recording[client] = status;

	// We literally cannot record atm...
	if (get_sourcetv_bot() == -1)
		return;

	for (int i = 1; i <= MaxClients; i++) {
		if (playerinfo_recording[i])
			players++;
	}

	if (players == 0 && stv_recording) {
		// Stop recording.
		log_client_status(client, prevstatus, status);
		ServerCommand("tv_stoprecord");
		stv_recording = false;

		if (icvar[CVAR_LOG]) {
			Format(line, sizeof(line), "Ended recording.");
			log_line(2);
		}

		// Don't log the player being removed twice.
		return;
	}
	else if (!stv_recording && players) {
		// Start recording.
		FormatTime(stv_demo_name, sizeof(stv_demo_name),
			"%Y_%m_%d__%H_%M_%S.dem", GetTime());

		ServerCommand("tv_record %s", stv_demo_name);
		stv_recording = true;

		if (icvar[CVAR_LOG]) {
			Format(line, sizeof(line), "Recording SourceTV demo \"%s\".", stv_demo_name);
			log_line(0);
		}
	}

	log_client_status(client, prevstatus, status);
}

void log_client_status(int client, bool prevstatus, bool status)
{
	char steamid[64];

	if (!icvar[CVAR_LOG] || !icvar[CVAR_ENABLE] || prevstatus == status)
		return;

	if (GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), true) == false)
		Format(steamid, sizeof(steamid), "Invalid_SteamID");

	Format(line, sizeof(line), "%s [%N | %s].", ((status) ? "Added  ": "Removed"), client, steamid);
	log_line(0);
}

void log_line(int newlines)
{
	Handle file;

	file = OpenFile("addons/sourcemod/logs/lilac_stv.log", "a");

	if (file == null) {
		PrintToServer("[Lilac SourceTV] Unable to open log file.");
		return;
	}

	for (int i = 0; line[i]; i++) {
		if (line[i] < 32)
			line[i] = '*';
	}

	for (int i = 0; i < newlines; i++)
		StrCat(line, sizeof(line), "\n");

	WriteFileLine(file, "%s", line);
	CloseHandle(file);
}

int get_sourcetv_bot()
{
	for (int i = 1; i <= MaxClients; i++) {
		if (!is_player_valid(i) || !IsClientSourceTV(i))
			continue;

		return i;
	}

	return -1;
}

public Action timer_restart_map(Handle timer)
{
	char mapname[256];

	if (!icvar[CVAR_ENABLE] || !icvar[CVAR_STV_JOIN])
		return;

	// Server may JUST have installed this plugin while players
	// 	are on the server.
	// 	Don't restart the map while there are players.
	if (GetGameTime() > 60.0) {
		int players = 0;

		for (int i = 1; i <= MaxClients; i++) {
			if (!is_player_valid(i) || IsFakeClient(i))
				continue;

			players++;
		}

		// Try again in 30 seconds.
		if (players > 2 && stv_restarted_map == false) {
			CreateTimer(30.0, timer_restart_map);

			return;
		}
	}

	// Map has already been restarted once, don't do it again.
	if (stv_restarted_map == true)
		return;

	// Prevent constant map restarts.
	stv_restarted_map = true;

	// Bot already in-game.
	if (get_sourcetv_bot() != -1)
		return;

	PrintToServer("[Lilac SourceTV] Restarting map to connect SourceTV Bot.");

	GetCurrentMap(mapname, sizeof(mapname));
	ServerCommand("changelevel \"%s\"", mapname);
}

public Action timer_decrement_aimbot(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (!is_player_valid(client))
		return;

	if (playerinfo_detections[client][INDEX_AIMBOT] > 0)
		playerinfo_detections[client][INDEX_AIMBOT]--;

	if (playerinfo_detections[client][INDEX_AIMBOT] == 0)
		update_recording_list(client, false);
}

public Action timer_decrement_aimlock(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (!is_player_valid(client))
		return;

	if (playerinfo_detections[client][INDEX_AIMLOCK] > 0)
		playerinfo_detections[client][INDEX_AIMLOCK]--;

	if (playerinfo_detections[client][INDEX_AIMLOCK] == 0)
		update_recording_list(client, false);
}

bool is_player_valid(int client)
{
	return (client >= 1 && client <= MaxClients
		&& IsClientConnected(client) && IsClientInGame(client));
}
