#pragma semicolon 1

#include <bTimes-core>

public Plugin:myinfo =
{
	name = "[bTimes] Zones",
	author = "blacky, cam",
	description = "Used to create map zones",
	version = VERSION,
	url = URL
}

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <smlib/entities>
#include <bTimes-timer>
#include <bTimes-random>
#include <bTimes-zones>

enum
{
	GameType_CSS,
	GameType_CSGO
};

new	Handle:g_DB,
	Handle:g_MapList,
	String:g_sMapName[64],
	Float:g_fSpawnPos[3],
	g_TotalZoneAllMaps[ZONE_COUNT];

// Zone properties
enum Properties
{
	Max,
	Count,
	Entity[64],
	bool:Ready[64],
	RowID[64],
	Flags[64],
	bool:Replaceable,
	bool:TriggerBased,
	String:Name[64],
	Color[4],
	HaloIndex,
	ModelIndex,
	Offset
};

new	g_Properties[ZONE_COUNT][Properties]; // Properties for each type of zone

// Zone setup
enum Setup
{
	bool:InZonesMenu,
	bool:InSetFlagsMenu,
	CurrentZone,
	Handle:SetupTimer,
	bool:Snapping,
	GridSnap,
	bool:ViewAnticheats
};

new	g_Setup[MAXPLAYERS + 1][Setup];

new	g_Entities_ZoneType[2048] = {-1, ...}, // For faster lookup of zone type by entity number
	g_Entities_ZoneNumber[2048] = {-1, ...}; // For faster lookup of zone number by entity number
new	Float:g_Zones[ZONE_COUNT][64][8][3], // Zones that have been created
	g_TotalZoneCount;

new	bool:g_bInside[MAXPLAYERS + 1][ZONE_COUNT][64];

new	g_SnapModelIndex,
	g_SnapHaloIndex;

// Zone drawing
#if defined SERVER
new	g_Drawing_Zone,
	g_Drawing_ZoneNumber;
#endif

// Cvars
new	Handle:g_hZoneColor[ZONE_COUNT],
	Handle:g_hZoneOffset[ZONE_COUNT],
	Handle:g_hZoneTexture[ZONE_COUNT],
	Handle:g_hZoneTrigger[ZONE_COUNT];

// Forwards
new	Handle:g_fwdOnZonesLoaded,
	Handle:g_fwdOnAllZonesLoaded,
	Handle:g_fwdOnZoneStartTouch,
	Handle:g_fwdOnZoneEndTouch;

// Chat
new	String:g_msg_start[128],
	String:g_msg_varcol[128],
	String:g_msg_textcol[128];


ConVar mp_do_warmup_period;

public OnPluginStart(){
	// Connect to database
	DB_Connect();

	// Cvars
	g_hZoneColor[MAIN_START]  = CreateConVar("timer_mainstart_color", "0 255 0 255", "Set the main start zone's RGBA color");
	g_hZoneColor[MAIN_END]    = CreateConVar("timer_mainend_color", "255 0 0 255", "Set the main end zone's RGBA color");
	g_hZoneColor[BONUS_START] = CreateConVar("timer_bonusstart_color", "0 255 0 255", "Set the bonus start zone's RGBA color");
	g_hZoneColor[BONUS_END]   = CreateConVar("timer_bonusend_color", "255 0 0 255", "Set the bonus end zone's RGBA color");
	g_hZoneColor[ANTICHEAT]   = CreateConVar("timer_ac_color", "255 255 0 255", "Set the anti-cheat zone's RGBA color");
	g_hZoneColor[FREESTYLE]   = CreateConVar("timer_fs_color", "0 0 255 255", "Set the freestyle zone's RGBA color");

	g_hZoneOffset[MAIN_START]  = CreateConVar("timer_mainstart_offset", "128", "Set the the default height for the main start zone.");
	g_hZoneOffset[MAIN_END]    = CreateConVar("timer_mainend_offset", "128", "Set the the default height for the main end zone.");
	g_hZoneOffset[BONUS_START] = CreateConVar("timer_bonusstart_offset", "128", "Set the the default height for the bonus start zone.");
	g_hZoneOffset[BONUS_END]   = CreateConVar("timer_bonusend_offset", "128", "Set the the default height for the bonus end zone.");
	g_hZoneOffset[ANTICHEAT]   = CreateConVar("timer_ac_offset", "0", "Set the the default height for the anti-cheat zone.");
	g_hZoneOffset[FREESTYLE]   = CreateConVar("timer_fs_offset", "0", "Set the the default height for the freestyle zone.");

	g_hZoneTexture[MAIN_START]  = CreateConVar("timer_mainstart_tex", "materials/sprites/trails/bluelightning", "Texture for main start zone. (Exclude the file types like .vmt/.vtf)");
	g_hZoneTexture[MAIN_END]    = CreateConVar("timer_mainend_tex", "materials/sprites/trails/bluelightning", "Texture for main end zone.");
	g_hZoneTexture[BONUS_START] = CreateConVar("timer_bonusstart_tex", "materials/sprites/trails/bluelightning", "Texture for bonus start zone.");
	g_hZoneTexture[BONUS_END]   = CreateConVar("timer_bonusend_tex", "materials/sprites/trails/bluelightning", "Texture for main end zone.");
	g_hZoneTexture[ANTICHEAT]   = CreateConVar("timer_ac_tex", "materials/sprites/trails/bluelightning", "Texture for anti-cheat zone.");
	g_hZoneTexture[FREESTYLE]   = CreateConVar("timer_fs_tex", "materials/sprites/trails/bluelightning", "Texture for freestyle zone.");

	g_hZoneTrigger[MAIN_START]  = CreateConVar("timer_mainstart_trigger", "0", "Main start zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
	g_hZoneTrigger[MAIN_END]    = CreateConVar("timer_mainend_trigger", "0", "Main end zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
	g_hZoneTrigger[BONUS_START] = CreateConVar("timer_bonusstart_trigger", "0", "Bonus start zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
	g_hZoneTrigger[BONUS_END]   = CreateConVar("timer_bonusend_trigger", "0", "Bonus end zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
	g_hZoneTrigger[ANTICHEAT]   = CreateConVar("timer_ac_trigger", "1", "Anti-cheat zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
	g_hZoneTrigger[FREESTYLE]   = CreateConVar("timer_fs_trigger", "1", "Freestyle zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);

	AutoExecConfig(true, "zones", "timer");

	// Hook changes
	for(new Zone = 0; Zone < ZONE_COUNT; Zone++)
	{
		HookConVarChange(g_hZoneColor[Zone], OnZoneColorChanged);
		HookConVarChange(g_hZoneOffset[Zone], OnZoneOffsetChanged);
		HookConVarChange(g_hZoneTrigger[Zone], OnZoneTriggerChanged);
	}

	// Admin Commands
	RegAdminCmd("sm_zones", SM_Zones, ADMFLAG_CUSTOM6, "Opens the zones menu.");

	// Player Commands
	RegConsoleCmdEx("sm_b", SM_B, "Teleports you to the bonus starting zone");
	RegConsoleCmdEx("sm_bonus", SM_B, "Teleports you to the bonus starting zone");
	RegConsoleCmdEx("sm_br", SM_B, "Teleports you to the bonus starting zone");
	RegConsoleCmdEx("sm_r", SM_R, "Teleports you to the starting zone");
	RegConsoleCmdEx("sm_restart", SM_R, "Teleports you to the starting zone");
	RegConsoleCmdEx("sm_respawn", SM_R, "Teleports you to the starting zone");
	RegConsoleCmdEx("sm_start", SM_R, "Teleports you to the starting zone");
	RegConsoleCmdEx("sm_end", SM_End, "Teleports you to the end zone");
	RegConsoleCmdEx("sm_endb", SM_EndB, "Teleports you to the bonus end zone");

	// Events
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart, EventHookMode_Pre);
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	// Natives
	CreateNative("Timer_InsideZone", Native_InsideZone);
	CreateNative("Timer_IsPointInsideZone", Native_IsPointInsideZone);
	CreateNative("Timer_TeleportToZone", Native_TeleportToZone);
	CreateNative("GetTotalZonesAllMaps", Native_GetTotalZonesAllMaps);

	// Forwards
	g_fwdOnZonesLoaded    = CreateGlobalForward("OnZonesLoaded", ET_Event);
	g_fwdOnAllZonesLoaded = CreateGlobalForward("OnAllZonesLoaded", ET_Event);
	g_fwdOnZoneStartTouch = CreateGlobalForward("OnZoneStartTouch", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnZoneEndTouch   = CreateGlobalForward("OnZoneEndTouch", ET_Event, Param_Cell, Param_Cell, Param_Cell);
}

/*
* Teleports a client to a zone, commented cause I think it causes my IDE to crash if I don't
*/
TeleportToZone(client, Zone, ZoneNumber, bool:bottom = false)
{
	StopTimer(client);

	if(g_Properties[Zone][Ready][ZoneNumber] == true)
	{
		new Float:vPos[3];
		GetZonePosition(Zone, ZoneNumber, vPos);

		if(bottom)
		{
			new Float:fBottom = (g_Zones[Zone][ZoneNumber][0][2] < g_Zones[Zone][ZoneNumber][7][2])?g_Zones[Zone][ZoneNumber][0][2]:g_Zones[Zone][ZoneNumber][7][2];

			TR_TraceRayFilter(vPos, Float:{90.0, 0.0, 0.0}, MASK_PLAYERSOLID_BRUSHONLY, RayType_Infinite, TraceRayDontHitSelf, client);

			if(TR_DidHit())
			{
				new Float:vHitPos[3];
				TR_GetEndPosition(vHitPos);

				if(vHitPos[2] < fBottom)
					vPos[2] = fBottom;
				else
					vPos[2] = vHitPos[2] + 0.5;
			}
			else
			{
				vPos[2] = fBottom;
			}
		}


		TeleportEntity(client, vPos, NULL_VECTOR, Float:{0.0, 0.0, 0.0});
	}
	else
	{
		TeleportEntity(client, g_fSpawnPos, NULL_VECTOR, Float:{0.0, 0.0, 0.0});
	}
}

public OnMapStart()
{
	if(g_MapList != INVALID_HANDLE)
		CloseHandle(g_MapList);

	g_MapList = ReadMapList();

	GetCurrentMap(g_sMapName, sizeof(g_sMapName));

	g_SnapHaloIndex = PrecacheModel("materials/sprites/halo01.vmt");
	g_SnapModelIndex = PrecacheModel("materials/sprites/trails/bluelightning.vmt");

	PrecacheModel("models/props/cs_office/vending_machine.mdl");

	CreateTimer(0.1, Timer_SnapPoint, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	#if defined SERVER
	CreateTimer(0.1, Timer_DrawBeams, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	#else
	CreateTimer(1.0, Timer_DrawBeams, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	#endif
}

public OnMapIDPostCheck()
{
	//if(GetGameType() == GameType_CSGO){
	//	CreateTimer(0.5, Timer_DB_LoadZones);
	//}
	//else
	//{
	DB_LoadZones();
	//}
}

public Action Timer_DB_LoadZones(Handle timer)
{
	DB_LoadZones();
}

public bool:OnClientConnect(client, String:rejectmsg[], maxlen)
{
	InitializePlayerProperties(client);

	return true;
}

public OnConfigsExecuted()
{
	for(new client = 1; client <= MaxClients; client++)
		InitializePlayerProperties(client);
}

public Action Event_RoundStart(Handle event, const char[] name, bool PreventBroadcast)
{
	InitializeZoneProperties();
	ResetEntities();

	DB_LoadZones();
}

public OnClientDisconnect(client)
{
	g_Setup[client][CurrentZone]    = -1;
	g_Setup[client][InZonesMenu]    = false;
	g_Setup[client][InSetFlagsMenu] = false;
}

public OnTimerChatChanged(MessageType, String:Message[])
{
	if(MessageType == 0)
	{
		Format(g_msg_start, sizeof(g_msg_start), Message);
		ReplaceMessage(g_msg_start, sizeof(g_msg_start));
	}
	else if(MessageType == 1)
	{
		Format(g_msg_varcol, sizeof(g_msg_varcol), Message);
		ReplaceMessage(g_msg_varcol, sizeof(g_msg_varcol));
	}
	else if(MessageType == 2)
	{
		Format(g_msg_textcol, sizeof(g_msg_textcol), Message);
		ReplaceMessage(g_msg_textcol, sizeof(g_msg_textcol));
	}
}

public OnZoneColorChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	for(new Zone; Zone < ZONE_COUNT; Zone++)
	{
		if(g_hZoneColor[Zone] == convar)
		{
			UpdateZoneColor(Zone);
			break;
		}
	}
}

public OnZoneOffsetChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	for(new Zone; Zone < ZONE_COUNT; Zone++)
	{
		if(g_hZoneOffset[Zone] == convar)
		{
			g_Properties[Zone][Offset] = StringToInt(newValue);
			break;
		}
	}
}

public OnZoneTriggerChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	for(new Zone; Zone < ZONE_COUNT; Zone++)
	{
		if(g_hZoneTrigger[Zone] == convar)
		{
			g_Properties[Zone][TriggerBased] = bool:StringToInt(newValue);
			break;
		}
	}
}

InitializeZoneProperties()
{
	g_TotalZoneCount     = 0;
	#if defined SERVER
	g_Drawing_Zone       = 0;
	g_Drawing_ZoneNumber = 0;
	#endif

	for(new Zone; Zone < ZONE_COUNT; Zone++)
	{
		GetZoneName(Zone, g_Properties[Zone][Name], 64);
		UpdateZoneColor(Zone);
		UpdateZoneBeamTexture(Zone);
		UpdateZoneSpriteTexture(Zone);
		g_Properties[Zone][Offset]       = GetConVarInt(g_hZoneOffset[Zone]);
		g_Properties[Zone][TriggerBased] = GetConVarBool(g_hZoneTrigger[Zone]);
		g_Properties[Zone][Count]        = 0;

		switch(Zone)
		{
			case MAIN_START, MAIN_END, BONUS_START, BONUS_END:
			{
				g_Properties[Zone][Max]         = 1;
				g_Properties[Zone][Replaceable] = true;
			}
			case ANTICHEAT, FREESTYLE:
			{
				g_Properties[Zone][Max]         = 64;
				g_Properties[Zone][Replaceable] = false;
			}
		}

		for(new i; i < g_Properties[Zone][Max]; i++)
		{
			g_Properties[Zone][Ready][i]  = false;
			g_Properties[Zone][RowID][i]  = 0;
			g_Properties[Zone][Entity][i] = -1;
			g_Properties[Zone][Flags][i]  = 0;
		}
	}
}

InitializePlayerProperties(client)
{
	g_Setup[client][CurrentZone]    = -1;
	g_Setup[client][ViewAnticheats] = false;
	g_Setup[client][Snapping]       = true;
	g_Setup[client][GridSnap]       = 64;
	g_Setup[client][InZonesMenu]    = false;
	g_Setup[client][InSetFlagsMenu] = false;
}

GetZoneName(Zone, String:buffer[], maxlength)
{
	switch(Zone)
	{
		case MAIN_START:
		{
			FormatEx(buffer, maxlength, "Main Start");
		}
		case MAIN_END:
		{
			FormatEx(buffer, maxlength, "Main End");
		}
		case BONUS_START:
		{
			FormatEx(buffer, maxlength, "Bonus Start");
		}
		case BONUS_END:
		{
			FormatEx(buffer, maxlength, "Bonus End");
		}
		case ANTICHEAT:
		{
			FormatEx(buffer, maxlength, "Anti-cheat");
		}
		case FREESTYLE:
		{
			FormatEx(buffer, maxlength, "Freestyle");
		}
		default:
		{
			FormatEx(buffer, maxlength, "Unknown");
		}
	}
}

UpdateZoneColor(Zone)
{
	decl String:sColor[32], String:sColorExp[4][8];

	GetConVarString(g_hZoneColor[Zone], sColor, sizeof(sColor));
	ExplodeString(sColor, " ", sColorExp, 4, 8);

	for(new i; i < 4; i++)
		g_Properties[Zone][Color][i] = StringToInt(sColorExp[i]);
}

UpdateZoneBeamTexture(Zone)
{
	decl String:sBuffer[PLATFORM_MAX_PATH];
	GetConVarString(g_hZoneTexture[Zone], sBuffer, PLATFORM_MAX_PATH);

	decl String:sBeam[PLATFORM_MAX_PATH];
	FormatEx(sBeam, PLATFORM_MAX_PATH, "%s.vmt", sBuffer);
	g_Properties[Zone][ModelIndex] = PrecacheModel(sBeam);
	AddFileToDownloadsTable(sBeam);

	FormatEx(sBeam, PLATFORM_MAX_PATH, "%s.vtf", sBuffer);
	AddFileToDownloadsTable(sBeam);
}

UpdateZoneSpriteTexture(Zone)
{
	decl String:sSprite[PLATFORM_MAX_PATH];

	FormatEx(sSprite, sizeof(sSprite), "materials/sprites/halo01.vmt");

	g_Properties[Zone][HaloIndex] = PrecacheModel(sSprite);
}

ResetEntities()
{
	for(new entity; entity < 2048; entity++)
	{
		g_Entities_ZoneType[entity]   = -1;
		g_Entities_ZoneNumber[entity] = -1;
	}
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(IsClientInGame(client))
	{
		if(g_Properties[MAIN_START][Ready][0] == true)
		{
			TeleportToZone(client, MAIN_START, 0, true);
		}
	}

	return Plugin_Continue;
}

public Action:SM_R(client, args)
{
	if(GetClientTeam(client) == CS_TEAM_SPECTATOR || GetClientTeam(client) == CS_TEAM_NONE || !IsPlayerAlive(client)){
		CS_SwitchTeam(client, CS_TEAM_T);

		CS_RespawnPlayer(client);
	}

	if(g_Properties[MAIN_START][Ready][0] == true)
	{
		StopTimer(client);
		TeleportToZone(client, MAIN_START, 0, true);

		if(g_Properties[MAIN_END][Ready][0] == true)
		{
			StartTimer(client, TIMER_MAIN);
		}
	}
	else
	{
		PrintColorText(client, "%s%sThe main start zone is not ready yet.",
			g_msg_start,
			g_msg_textcol);
	}

	return Plugin_Handled;
}

public Action:SM_End(client, args)
{
	if(GetClientTeam(client) == CS_TEAM_SPECTATOR || GetClientTeam(client) == CS_TEAM_NONE || !IsPlayerAlive(client)){
		CS_SwitchTeam(client, CS_TEAM_T);

		CS_RespawnPlayer(client);
	}

	if(g_Properties[MAIN_END][Ready][0] == true)
	{
		StopTimer(client);
		TeleportToZone(client, MAIN_END, 0, true);
	}
	else
	{
		PrintColorText(client, "%s%sThe main end zone is not ready yet.",
			g_msg_start,
			g_msg_textcol);
	}

	return Plugin_Handled;
}

public Action:SM_B(client, args)
{
	if(GetClientTeam(client) == CS_TEAM_SPECTATOR || GetClientTeam(client) == CS_TEAM_NONE || !IsPlayerAlive(client)){
		CS_SwitchTeam(client, CS_TEAM_T);

		CS_RespawnPlayer(client);
	}

	if(g_Properties[BONUS_START][Ready][0] == true)
	{
		StopTimer(client);
		TeleportToZone(client, BONUS_START, 0, true);

		if(g_Properties[BONUS_END][Ready][0] == true)
		{
			StartTimer(client, TIMER_BONUS);
		}
	}
	else
	{
		PrintColorText(client, "%s%sThe bonus zone has not been created.",
			g_msg_start,
			g_msg_textcol);
	}

	return Plugin_Handled;
}

public Action:SM_EndB(client, args)
{
	if(GetClientTeam(client) == CS_TEAM_SPECTATOR || GetClientTeam(client) == CS_TEAM_NONE || !IsPlayerAlive(client)){
		CS_SwitchTeam(client, CS_TEAM_T);

		CS_RespawnPlayer(client);
	}

	if(g_Properties[BONUS_END][Ready][0] == true)
	{
		StopTimer(client);
		TeleportToZone(client, BONUS_END, 0, true);
	}
	else
	{
		PrintColorText(client, "%s%sThe bonus end zone has not been created.",
			g_msg_start,
			g_msg_textcol);
	}

	return Plugin_Handled;
}

public Action:SM_Zones(client, args)
{
	OpenZonesMenu(client);

	return Plugin_Handled;
}

OpenZonesMenu(client)
{
	new Handle:menu = CreateMenu(Menu_Zones);

	SetMenuTitle(menu, "Zone Control");

	AddMenuItem(menu, "add", "Add a zone");
	AddMenuItem(menu, "goto", "Go to zone");
	AddMenuItem(menu, "del", "Delete a zone");
	AddMenuItem(menu, "set", "Set zone flags");
	AddMenuItem(menu, "snap", g_Setup[client][Snapping]?"Wall Snapping: On":"Wall Snapping: Off");

	decl String:sDisplay[64];
	IntToString(g_Setup[client][GridSnap], sDisplay, sizeof(sDisplay));
	Format(sDisplay, sizeof(sDisplay), "Grid Snapping: %s", sDisplay);
	AddMenuItem(menu, "grid", sDisplay);
	AddMenuItem(menu, "ac", g_Setup[client][ViewAnticheats]?"Anti-cheats: Visible":"Anti-cheats: Invisible");

	DisplayMenu(menu, client, MENU_TIME_FOREVER);

	g_Setup[client][InZonesMenu] = true;
}

public Menu_Zones(Handle:menu, MenuAction:action, client, param2)
{
	if(action & MenuAction_Select)
	{
		decl String:info[32];
		GetMenuItem(menu, param2, info, sizeof(info));

		if(StrEqual(info, "add"))
		{
			OpenAddZoneMenu(client);
		}
		else if(StrEqual(info, "goto"))
		{
			OpenGoToMenu(client);
		}
		else if(StrEqual(info, "del"))
		{
			OpenDeleteMenu(client);
		}
		else if(StrEqual(info, "set"))
		{
			OpenSetFlagsMenu(client);
		}
		else if(StrEqual(info, "snap"))
		{
			g_Setup[client][Snapping] = !g_Setup[client][Snapping];
			OpenZonesMenu(client);
		}
		else if(StrEqual(info, "grid"))
		{
			g_Setup[client][GridSnap] *= 2;

			if(g_Setup[client][GridSnap] > 64)
				g_Setup[client][GridSnap] = 1;

			OpenZonesMenu(client);
		}
		else if(StrEqual(info, "ac"))
		{
			g_Setup[client][ViewAnticheats] = !g_Setup[client][ViewAnticheats];
			OpenZonesMenu(client);
		}
	}

	if(action & MenuAction_End)
	{
		CloseHandle(menu);
	}

	if(action & MenuAction_Cancel)
	{
		if(param2 == MenuCancel_Exit)
		{
			g_Setup[client][InZonesMenu] = false;
		}
	}
}

OpenAddZoneMenu(client)
{
	new Handle:menu = CreateMenu(Menu_AddZone);
	SetMenuTitle(menu, "Add a Zone");

	decl String:sInfo[8];
	for(new Zone; Zone < ZONE_COUNT; Zone++)
	{
		IntToString(Zone, sInfo, sizeof(sInfo));
		AddMenuItem(menu, sInfo, g_Properties[Zone][Name]);
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Menu_AddZone(Handle:menu, MenuAction:action, client, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:info[32];
		GetMenuItem(menu, param2, info, sizeof(info));

		CreateZone(client, StringToInt(info));

		OpenAddZoneMenu(client);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			OpenZonesMenu(client);
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	if(action & MenuAction_Cancel)
	{
		if(param2 == MenuCancel_Exit)
		{
			g_Setup[client][InZonesMenu] = false;
		}
	}
}

CreateZone(client, Zone)
{
	if(ClientCanCreateZone(client, Zone))
	{
		if((g_Properties[Zone][Count] < g_Properties[Zone][Max]) || g_Properties[Zone][Replaceable] == true)
		{
			new ZoneNumber;

			if(g_Properties[Zone][Count] >= g_Properties[Zone][Max])
				ZoneNumber = 0;
			else
				ZoneNumber = g_Properties[Zone][Count];

			if(g_Setup[client][CurrentZone] == -1)
			{
				if(g_Properties[Zone][Ready][ZoneNumber] == true)
					DB_DeleteZone(client, Zone, ZoneNumber);

				if(Zone == ANTICHEAT)
					g_Setup[client][ViewAnticheats] = true;

				g_Setup[client][CurrentZone] = Zone;

				GetZoneSetupPosition(client, g_Zones[Zone][ZoneNumber][0]);

				new Handle:data;
				g_Setup[client][SetupTimer] = CreateDataTimer(0.1, Timer_ZoneSetup, data, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
				WritePackCell(data, GetClientUserId(client));
				WritePackCell(data, ZoneNumber);
			}
			else if(g_Setup[client][CurrentZone] == Zone)
			{
				if(g_Properties[Zone][Count] < g_Properties[Zone][Max])
				{
					g_Properties[Zone][Count]++;
					g_TotalZoneCount++;
				}

				KillTimer(g_Setup[client][SetupTimer], true);

				GetZoneSetupPosition(client, g_Zones[Zone][ZoneNumber][7]);

				g_Zones[Zone][ZoneNumber][7][2] += g_Properties[Zone][Offset];

				g_Setup[client][CurrentZone] = -1;
				g_Properties[Zone][Ready][ZoneNumber] = true;

				DB_SaveZone(Zone, ZoneNumber);

				if(g_Properties[Zone][TriggerBased] == true)
					CreateZoneTrigger(Zone, ZoneNumber);
			}
			else
			{
				PrintColorText(client, "%s%sYou are already setting up a different zone (%s%s%s).",
					g_msg_start,
					g_msg_textcol,
					g_msg_varcol,
					g_Properties[g_Setup[client][CurrentZone]][Name],
					g_msg_textcol);
			}
		}
		else
		{
			PrintColorText(client, "%s%sThere are too many of this zone (Max %s%d%s).",
				g_msg_start,
				g_msg_textcol,
				g_msg_varcol,
				g_Properties[Zone][Max],
				g_msg_textcol);
		}
	}
	else
	{
		PrintColorText(client, "%s%sSomeone else is already creating this zone (%s%s%s).",
			g_msg_start,
			g_msg_textcol,
			g_msg_varcol,
			g_Properties[Zone][Name],
			g_msg_textcol);
	}
}

bool:ClientCanCreateZone(client, Zone)
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if(g_Setup[i][CurrentZone] == Zone && client != i)
		{
			return false;
		}
	}

	return true;
}

public Action:Timer_ZoneSetup(Handle:timer, Handle:pack)
{
	ResetPack(pack);
	new client = GetClientOfUserId(ReadPackCell(pack));

	if(client != 0)
	{
		new ZoneNumber = ReadPackCell(pack);
		new Zone       = g_Setup[client][CurrentZone];

		// Get setup position
		GetZoneSetupPosition(client, g_Zones[Zone][ZoneNumber][7]);
		g_Zones[Zone][ZoneNumber][7][2] += g_Properties[Zone][Offset];

		// Draw zone
		CreateZonePoints(g_Zones[Zone][ZoneNumber]);
		DrawZone(Zone, ZoneNumber, 0.1);
	}
	else
	{
		KillTimer(timer, true);
	}
}

CreateZonePoints(Float:Zone[8][3])
{
	for(new i=1; i<7; i++)
	{
		for(new j=0; j<3; j++)
		{
			Zone[i][j] = Zone[((i >> (2 - j)) & 1) * 7][j];
		}
	}
}

DrawZone(Zone, ZoneNumber, Float:life)
{
	new color[4];

	for(new i = 0; i < 4; i++)
		color[i] = g_Properties[Zone][Color][i];

	for(new i=0, i2=3; i2>=0; i+=i2--)
	{
		for(new j=1; j<=7; j+=(j/2)+1)
		{
			if(j != 7-i)
			{
				#if defined SERVER
				TE_SetupBeamPoints(g_Zones[Zone][ZoneNumber][i], g_Zones[Zone][ZoneNumber][j], g_Properties[Zone][ModelIndex], g_Properties[Zone][HaloIndex], 0, 0, (life < 0.1)?0.1:life, 5.0, 5.0, 10, 0.0, color, 0);
				#else
				TE_SetupBeamPoints(g_Zones[Zone][ZoneNumber][i], g_Zones[Zone][ZoneNumber][j], g_Properties[Zone][ModelIndex], g_Properties[Zone][HaloIndex], 0, 0, life, 5.0, 5.0, 10, 0.0, color, 0);
				#endif
				new clients[MaxClients], numClients;

				switch(Zone)
				{
					case MAIN_START, MAIN_END, BONUS_START, BONUS_END, FREESTYLE:
					{
						TE_SendToAll();
					}
					case ANTICHEAT:
					{
						for(new client = 1; client <= MaxClients; client++)
							if(IsClientInGame(client) && g_Setup[client][ViewAnticheats] == true)
								clients[numClients++] = client;

						if(numClients > 0)
							TE_Send(clients, numClients);
					}
				}
			}
		}
	}
}

public Action:Timer_DrawBeams(Handle:timer, any:data)
{
	// Draw 4 zones (32 temp ents limit) per timer frame so all zones will draw
	#if defined SERVER
	if(g_TotalZoneCount > 0)
	{
		new ZonesDrawnThisFrame;

		for(new cycle; cycle < ZONE_COUNT; g_Drawing_Zone = (g_Drawing_Zone + 1) % ZONE_COUNT, cycle++)
		{
			for(; g_Drawing_ZoneNumber < g_Properties[g_Drawing_Zone][Count]; g_Drawing_ZoneNumber++)
			{
				if(g_Properties[g_Drawing_Zone][Ready][g_Drawing_ZoneNumber] == true)
				{
					DrawZone(g_Drawing_Zone, g_Drawing_ZoneNumber, (float(g_TotalZoneCount)/40.0) + 0.3);

					if(++ZonesDrawnThisFrame == 4)
					{
						g_Drawing_ZoneNumber++;

						return Plugin_Continue;
					}
				}
			}

			g_Drawing_ZoneNumber = 0;
		}
	}
	#else
	for(new Zone; Zone < ZONE_COUNT; Zone++){
		for(new ZoneNumber; ZoneNumber < g_Properties[Zone][Count]; ZoneNumber++){
			if(g_Properties[Zone][Ready][ZoneNumber] == true)
				DrawZone(Zone, ZoneNumber, 1.1);
		}
	}
	#endif

	return Plugin_Continue;
}

CreateZoneTrigger(Zone, ZoneNumber)
{
	new entity = CreateEntityByName("trigger_multiple");
	if(entity != -1)
	{
		SetEntityModel(entity, "models/props/cs_office/vending_machine.mdl");

		//DispatchKeyValue(entity, "spawnflags", "4097");
		DispatchKeyValue(entity, "spawnflags", "257");
		DispatchKeyValue(entity, "StartDisabled", "0");

		DispatchSpawn(entity);
		ActivateEntity(entity);

		new Float:fPos[3];
		GetZonePosition(Zone, ZoneNumber, fPos);
		TeleportEntity(entity, fPos, NULL_VECTOR, NULL_VECTOR);

		new Float:fBounds[2][3];
		GetMinMaxBounds(Zone, ZoneNumber, fBounds);
		SetEntPropVector(entity, Prop_Send, "m_vecMins", fBounds[0]);
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", fBounds[1]);

		SetEntProp(entity, Prop_Send, "m_nSolidType", 2);
		//SetEntProp(entity, Prop_Send, "m_fEffects", GetEntProp(entity, Prop_Send, "m_fEffects") | 32);

		g_Entities_ZoneType[entity]            = Zone;
		g_Entities_ZoneNumber[entity]          = ZoneNumber;
		g_Properties[Zone][Entity][ZoneNumber] = entity;

		SDKHook(entity, SDKHook_StartTouch, Hook_StartTouch);
		SDKHook(entity, SDKHook_EndTouch, Hook_EndTouch);
		SDKHook(entity, SDKHook_Touch, Hook_Touch);
	}
}

public Action:Hook_StartTouch(entity, other)
{
	// Anti-cheats, freestyles, and end zones
	new Zone       = g_Entities_ZoneType[entity];
	new ZoneNumber = g_Entities_ZoneNumber[entity];

	if(0 < other <= MaxClients)
	{
		if(IsClientInGame(other))
		{
			if(IsPlayerAlive(other))
			{
				if(g_Properties[Zone][TriggerBased] == true)
				{
					g_bInside[other][Zone][ZoneNumber] = true;

					switch(Zone)
					{
						case MAIN_END:
						{
							if(IsBeingTimed(other, TIMER_MAIN))
								FinishTimer(other);
						}
						case BONUS_END:
						{
							if(IsBeingTimed(other, TIMER_BONUS))
								FinishTimer(other);
						}
						case ANTICHEAT:
						{
							if(IsBeingTimed(other, TIMER_MAIN) && (g_Properties[Zone][Flags][ZoneNumber] & FLAG_ANTICHEAT_MAIN))
							{
								StopTimer(other);

								PrintColorText(other, "%s%sYour timer was stopped for using a shortcut.",
									g_msg_start,
									g_msg_textcol);
							}

							if(IsBeingTimed(other, TIMER_BONUS) && (g_Properties[Zone][Flags][ZoneNumber] & FLAG_ANTICHEAT_BONUS))
							{
								StopTimer(other);

								PrintColorText(other, "%s%sYour timer was stopped for using a shortcut.",
									g_msg_start,
									g_msg_textcol);
							}
						}
					}
				}
			}

			if(g_Setup[other][InSetFlagsMenu] == true){
				if(Zone == ANTICHEAT || Zone == FREESTYLE)
					OpenSetFlagsMenu(other, Zone, ZoneNumber);
			}
			Call_StartForward(g_fwdOnZoneStartTouch);
			Call_PushCell(other);
			Call_PushCell(Zone);
			Call_PushCell(ZoneNumber);
			Call_Finish();
		}
	}
}

public Action:Hook_EndTouch(entity, other)
{
	new Zone       = g_Entities_ZoneType[entity];
	new ZoneNumber = g_Entities_ZoneNumber[entity];

	if(0 < other <= MaxClients)
	{
		if(g_Properties[Zone][TriggerBased] == true)
		{
			g_bInside[other][Zone][ZoneNumber] = false;
		}

		if(g_Setup[other][InSetFlagsMenu] == true){
			if(Zone == ANTICHEAT || Zone == FREESTYLE)
				OpenSetFlagsMenu(other, Zone, ZoneNumber);
		}

		Call_StartForward(g_fwdOnZoneEndTouch);
		Call_PushCell(other);
		Call_PushCell(Zone);
		Call_PushCell(ZoneNumber);
		Call_Finish();
	}
}


public Action:Hook_Touch(entity, other)
{
	// Anti-prespeed (Start zones)
	new Zone = g_Entities_ZoneType[entity];
	new ZoneNumber = g_Entities_ZoneNumber[entity];

	if(g_Properties[Zone][TriggerBased] == true && (0 < other <= MaxClients))
	{
		if(IsClientInGame(other))
		{
			if(IsPlayerAlive(other))
			{
				switch(Zone)
				{
					case MAIN_START:
					{
						if(g_Properties[MAIN_END][Ready][0] == true)
							StartTimer(other, TIMER_MAIN);
					}
					case BONUS_START:
					{
						if(g_Properties[BONUS_END][Ready][0] == true)
							StartTimer(other, TIMER_BONUS);
					}
				}

				if(g_Setup[other][InSetFlagsMenu] == true){
					if(Zone == ANTICHEAT || Zone == FREESTYLE)
						OpenSetFlagsMenu(other, Zone, ZoneNumber);
				}
			}
		}
	}
}

GetZoneSetupPosition(client, Float:fPos[3])
{
	new bool:bSnapped;

	if(g_Setup[client][Snapping] == true)
		bSnapped = GetWallSnapPosition(client, fPos);

	if(bSnapped == false)
		GetGridSnapPosition(client, fPos);
}

GetGridSnapPosition(client, Float:fPos[3])
{
	Entity_GetAbsOrigin(client, fPos);

	for(new i = 0; i < 2; i++)
		fPos[i] = float(RoundFloat(fPos[i] / float(g_Setup[client][GridSnap])) * g_Setup[client][GridSnap]);

	// Snap to z axis only if the client is off the ground
	if(!(GetEntityFlags(client) & FL_ONGROUND))
		fPos[2] = float(RoundFloat(fPos[2] / float(g_Setup[client][GridSnap])) * g_Setup[client][GridSnap]);
}

public Action:Timer_SnapPoint(Handle:timer, any:data)
{
	new Float:fSnapPos[3], Float:fClientPos[3];

	for(new client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) && !IsFakeClient(client) && g_Setup[client][InZonesMenu])
		{
			Entity_GetAbsOrigin(client, fClientPos);
			GetZoneSetupPosition(client, fSnapPos);

			if(GetVectorDistance(fClientPos, fSnapPos) > 0)
			{
				TE_SetupBeamPoints(fClientPos, fSnapPos, g_SnapModelIndex, g_SnapHaloIndex, 0, 0, 0.1, 5.0, 5.0, 0, 0.0, {0, 255, 255, 255}, 0);
				TE_SendToAll();
			}
		}
	}
}

bool:GetWallSnapPosition(client, Float:fPos[3])
{
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", fPos);

	new Float:fHitPos[3], Float:vAng[3], bool:bSnapped;

	for(; vAng[1] < 360; vAng[1] += 90)
	{
		TR_TraceRayFilter(fPos, vAng, MASK_PLAYERSOLID_BRUSHONLY, RayType_Infinite, TraceRayDontHitSelf, client);

		if(TR_DidHit())
		{
			TR_GetEndPosition(fHitPos);

			if(GetVectorDistance(fPos, fHitPos) < 17)
			{
				if(vAng[1] == 0 || vAng[1] == 180)
				{
					// Change x
					fPos[0] = fHitPos[0];
				}
				else
				{
					// Change y
					fPos[1] = fHitPos[1];
				}

				bSnapped = true;
			}
		}
	}

	return bSnapped;
}

public bool:TraceRayDontHitSelf(entity, mask, any:data)
{
	return entity != data && !(0 < entity <= MaxClients);
}

GetZonePosition(Zone, ZoneNumber, Float:fPos[3])
{
	for(new i = 0; i < 3; i++)
		fPos[i] = (g_Zones[Zone][ZoneNumber][0][i] + g_Zones[Zone][ZoneNumber][7][i]) / 2;
}

GetMinMaxBounds(Zone, ZoneNumber, Float:fBounds[2][3])
{
	new Float:length;

	for(new i = 0; i < 3; i++)
	{
		length = FloatAbs(g_Zones[Zone][ZoneNumber][0][i] - g_Zones[Zone][ZoneNumber][7][i]);
		fBounds[0][i] = -(length / 2);
		fBounds[1][i] = length / 2;
	}
}

DB_Connect()
{
	if(g_DB != INVALID_HANDLE)
		CloseHandle(g_DB);

	decl String:error[255];
	g_DB = SQL_Connect("timer", true, error, sizeof(error));

	if(g_DB == INVALID_HANDLE)
	{
		LogError(error);
		CloseHandle(g_DB);
	}
}

DB_LoadZones()
{
	decl String:query[512];
	FormatEx(query, sizeof(query), "SELECT Type, RowID, flags, point00, point01, point02, point10, point11, point12 FROM zones WHERE MapID = (SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1)",
		g_sMapName);
	SQL_TQuery(g_DB, LoadZones_Callback, query, _, DBPrio_High);
}

public LoadZones_Callback(Handle:owner, Handle:hndl, String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		new Zone, ZoneNumber;

		while(SQL_FetchRow(hndl))
		{
			Zone       = SQL_FetchInt(hndl, 0);
			ZoneNumber = g_Properties[Zone][Count];

			g_Properties[Zone][RowID][ZoneNumber] = SQL_FetchInt(hndl, 1);
			g_Properties[Zone][Flags][ZoneNumber] = SQL_FetchInt(hndl, 2);

			for(new i = 0; i < 6; i++)
			{
				g_Zones[Zone][ZoneNumber][(i / 3) * 7][i % 3] = SQL_FetchFloat(hndl, i + 3);
			}

			CreateZonePoints(g_Zones[Zone][ZoneNumber]);
			CreateZoneTrigger(Zone, ZoneNumber);

			g_Properties[Zone][Ready][ZoneNumber] = true;
			g_Properties[Zone][Count]++;
			g_TotalZoneCount++;
		}

		Call_StartForward(g_fwdOnZonesLoaded);
		Call_Finish();

		for(int i = 1; i <= MaxClients; i++){
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i))
				TeleportToZone(i, MAIN_START, 0, true);
		}

		decl String:sQuery[128];
		FormatEx(sQuery, sizeof(sQuery), "SELECT MapID, Type FROM zones");
		SQL_TQuery(g_DB, LoadZones_Callback2, sQuery);
	}
	else
	{
		LogError(error);
	}
}

public LoadZones_Callback2(Handle:owner, Handle:hndl, String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		for(new Zone; Zone < ZONE_COUNT; Zone++)
			g_TotalZoneAllMaps[Zone] = 0;

		new MapID;
		decl String:sMapName[64];
		while(SQL_FetchRow(hndl))
		{
			MapID = SQL_FetchInt(hndl, 0);

			GetMapNameFromMapId(MapID, sMapName, sizeof(sMapName));

			if(FindStringInArray(g_MapList, sMapName) != -1)
			{
				g_TotalZoneAllMaps[SQL_FetchInt(hndl, 1)]++;
			}
		}

		Call_StartForward(g_fwdOnAllZonesLoaded);
		Call_Finish();
	}
	else
	{
		LogError(error);
	}
}

DB_SaveZone(Zone, ZoneNumber)
{
	new Handle:data = CreateDataPack();
	WritePackCell(data, Zone);
	WritePackCell(data, ZoneNumber);

	decl String:query[512];
	FormatEx(query, sizeof(query), "INSERT INTO zones (MapID, Type, point00, point01, point02, point10, point11, point12, flags) VALUES ((SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1), %d, %f, %f, %f, %f, %f, %f, %d)",
		g_sMapName,
		Zone,
		g_Zones[Zone][ZoneNumber][0][0], g_Zones[Zone][ZoneNumber][0][1], g_Zones[Zone][ZoneNumber][0][2],
		g_Zones[Zone][ZoneNumber][7][0], g_Zones[Zone][ZoneNumber][7][1], g_Zones[Zone][ZoneNumber][7][2],
		g_Properties[Zone][Flags][ZoneNumber]);
	SQL_TQuery(g_DB, SaveZone_Callback, query, data);
}

public SaveZone_Callback(Handle:owner, Handle:hndl, String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		ResetPack(data);
		new Zone       = ReadPackCell(data);
		new ZoneNumber = ReadPackCell(data);

		g_Properties[Zone][RowID][ZoneNumber] = SQL_GetInsertId(hndl);
	}
	else
	{
		LogError(error);
	}

	CloseHandle(data);
}

DB_DeleteZone(client, Zone, ZoneNumber, bool:ManualDelete = false)
{
	if(g_Properties[Zone][Ready][ZoneNumber] == true)
	{
		// Delete from database
		new Handle:data = CreateDataPack();
		WritePackCell(data, GetClientUserId(client));
		WritePackCell(data, Zone);

		decl String:query[512];
		FormatEx(query, sizeof(query), "DELETE FROM zones WHERE RowID = %d",
			g_Properties[Zone][RowID][ZoneNumber]);
		SQL_TQuery(g_DB, DeleteZone_Callback, query, data);


		// Delete in memory
		for(new client2 = 1; client2 <= MaxClients; client2++)
		{
			g_bInside[client2][Zone][ZoneNumber] = false;

			if(ManualDelete == true)
			{
				if(Zone == MAIN_START || Zone == MAIN_END)
				{
					if(IsBeingTimed(client2, TIMER_MAIN))
					{
						StopTimer(client2);

						PrintColorText(client2, "%s%sYour timer was stopped because the %s%s%s zone was deleted.",
							g_msg_start,
							g_msg_textcol,
							g_msg_varcol,
							g_Properties[Zone][Name],
							g_msg_textcol);
					}
				}

				if(Zone == BONUS_START || Zone == BONUS_END)
				{
					if(IsBeingTimed(client2, TIMER_BONUS))
					{
						StopTimer(client2);

						PrintColorText(client2, "%s%sYour timer was stopped because the %s%s%s zone was deleted.",
							g_msg_start,
							g_msg_textcol,
							g_msg_varcol,
							g_Properties[Zone][Name],
							g_msg_textcol);
					}
				}
			}
		}

		if(IsValidEntity(g_Properties[Zone][Entity][ZoneNumber]))
		{
			AcceptEntityInput(g_Properties[Zone][Entity][ZoneNumber], "Kill");
		}

		if(-1 < g_Properties[Zone][Entity][ZoneNumber] < 2048)
		{
			g_Entities_ZoneNumber[g_Properties[Zone][Entity][ZoneNumber]] = -1;
			g_Entities_ZoneType[g_Properties[Zone][Entity][ZoneNumber]]   = -1;
		}

		for(new i = ZoneNumber; i < g_Properties[Zone][Count] - 1; i++)
		{
			for(new point = 0; point < 8; point++)
				for(new axis = 0; axis < 3; axis++)
					g_Zones[Zone][i][point][axis] = g_Zones[Zone][i + 1][point][axis];

			g_Properties[Zone][Entity][i] = g_Properties[Zone][Entity][i + 1];

			if(-1 < g_Properties[Zone][Entity][i] < 2048)
			{
				g_Entities_ZoneNumber[g_Properties[Zone][Entity][i]]--;
			}

			g_Properties[Zone][RowID][i]  = g_Properties[Zone][RowID][i + 1];
			g_Properties[Zone][Flags][i]  = g_Properties[Zone][Flags][i + 1];

		}

		g_Properties[Zone][Ready][g_Properties[Zone][Count] - 1] = false;

		g_Properties[Zone][Count]--;
		g_TotalZoneCount--;
	}
	else
	{
		PrintColorText(client, "%s%sAttempted to delete a zone that doesn't exist.",
			g_msg_start,
			g_msg_textcol);
	}
}

public DeleteZone_Callback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		ResetPack(data);
		new userid = ReadPackCell(data);
		new client = GetClientOfUserId(userid);

		if(client != 0)
		{
			new Zone = ReadPackCell(data);
			LogMessage("%L deleted zone %s", client, g_Properties[Zone][Name]);
		}
		else
		{
			LogMessage("Player with UserID %d deleted a zone.", userid);
		}
	}
	else
	{
		LogError(error);
	}

	CloseHandle(data);
}

OpenGoToMenu(client)
{
	if(g_TotalZoneCount > 0)
	{
		new Handle:menu = CreateMenu(Menu_GoToZone);

		SetMenuTitle(menu, "Go to a Zone");

		decl String:sInfo[8];
		for(new Zone; Zone < ZONE_COUNT; Zone++)
		{
			if(g_Properties[Zone][Count] > 0)
			{
				IntToString(Zone, sInfo, sizeof(sInfo));
				AddMenuItem(menu, sInfo, g_Properties[Zone][Name]);
			}
		}

		SetMenuExitBackButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
	else
	{
		OpenZonesMenu(client);
	}
}

public Menu_GoToZone(Handle:menu, MenuAction:action, client, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:info[32];
		GetMenuItem(menu, param2, info, sizeof(info));

		new Zone = StringToInt(info);

		switch(Zone)
		{
			case MAIN_START, MAIN_END, BONUS_START, BONUS_END:
			{
				TeleportToZone(client, Zone, 0);
				OpenGoToMenu(client);
			}
			case ANTICHEAT, FREESTYLE:
			{
				ListGoToZones(client, Zone);
			}
		}
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			OpenZonesMenu(client);
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	if(action & MenuAction_Cancel)
	{
		if(param2 == MenuCancel_Exit)
		{
			g_Setup[client][InZonesMenu] = false;
		}
	}
}

ListGoToZones(client, Zone)
{
	new Handle:menu = CreateMenu(Menu_GoToList);
	SetMenuTitle(menu, "Go to %s zones", g_Properties[Zone][Name]);

	decl String:sInfo[16], String:sDisplay[16];
	for(new ZoneNumber; ZoneNumber < g_Properties[Zone][Count]; ZoneNumber++)
	{
		FormatEx(sInfo, sizeof(sInfo), "%d;%d", Zone, ZoneNumber);
		IntToString(ZoneNumber + 1, sDisplay, sizeof(sDisplay));

		AddMenuItem(menu, sInfo, sDisplay);
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Menu_GoToList(Handle:menu, MenuAction:action, client, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:info[32];
		GetMenuItem(menu, param2, info, sizeof(info));

		decl String:sZoneAndNumber[2][16];
		ExplodeString(info, ";", sZoneAndNumber, 2, 16);

		new Zone       = StringToInt(sZoneAndNumber[0]);
		new ZoneNumber = StringToInt(sZoneAndNumber[1]);

		TeleportToZone(client, Zone, ZoneNumber);

		ListGoToZones(client, Zone);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			OpenGoToMenu(client);
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	if(action & MenuAction_Cancel)
	{
		if(param2 == MenuCancel_Exit)
		{
			g_Setup[client][InZonesMenu] = false;
		}
	}
}

OpenDeleteMenu(client)
{
	if(g_TotalZoneCount > 0)
	{
		new Handle:menu = CreateMenu(Menu_DeleteZone);

		SetMenuTitle(menu, "Delete a Zone");

		AddMenuItem(menu, "sel", "Selected Zone");

		decl String:sInfo[8];
		for(new Zone = 0; Zone < ZONE_COUNT; Zone++)
		{
			if(g_Properties[Zone][Count] > 0)
			{
				IntToString(Zone, sInfo, sizeof(sInfo));

				AddMenuItem(menu, sInfo, g_Properties[Zone][Name]);
			}
		}

		SetMenuExitBackButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
	else
	{
		OpenZonesMenu(client);
	}
}

public Menu_DeleteZone(Handle:menu, MenuAction:action, client, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:info[32];
		GetMenuItem(menu, param2, info, sizeof(info));

		if(StrEqual(info, "sel"))
		{
			for(new Zone = 0; Zone < ZONE_COUNT; Zone++)
			{
				for(new ZoneNumber = 0; ZoneNumber < g_Properties[Zone][Count]; ZoneNumber++)
				{
					if(g_bInside[client][Zone][ZoneNumber] == true)
					{
						DB_DeleteZone(client, Zone, ZoneNumber, true);
					}
				}
			}

			OpenDeleteMenu(client);
		}
		else
		{
			new Zone = StringToInt(info);

			switch(Zone)
			{
				case MAIN_START, MAIN_END, BONUS_START, BONUS_END:
				{
					DB_DeleteZone(client, Zone, 0, true);

					OpenDeleteMenu(client);
				}
				case ANTICHEAT, FREESTYLE:
				{
					ListDeleteZones(client, Zone);
				}
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			OpenZonesMenu(client);
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	if(action & MenuAction_Cancel)
	{
		if(param2 == MenuCancel_Exit)
		{
			g_Setup[client][InZonesMenu] = false;
		}
	}
}

ListDeleteZones(client, Zone)
{
	new Handle:menu = CreateMenu(Menu_DeleteList);
	SetMenuTitle(menu, "Delete %s zones", g_Properties[Zone][Name]);

	decl String:sInfo[16], String:sDisplay[16];
	for(new ZoneNumber = 0; ZoneNumber < g_Properties[Zone][Count]; ZoneNumber++)
	{
		FormatEx(sInfo, sizeof(sInfo), "%d;%d", Zone, ZoneNumber);
		IntToString(ZoneNumber + 1, sDisplay, sizeof(sDisplay));

		AddMenuItem(menu, sInfo, sDisplay);
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Menu_DeleteList(Handle:menu, MenuAction:action, client, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:info[32];
		GetMenuItem(menu, param2, info, sizeof(info));

		decl String:sZoneAndNumber[2][16];
		ExplodeString(info, ";", sZoneAndNumber, 2, 16);

		new Zone       = StringToInt(sZoneAndNumber[0]);
		new ZoneNumber = StringToInt(sZoneAndNumber[1]);

		DB_DeleteZone(client, Zone, ZoneNumber);

		ListDeleteZones(client, Zone);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			OpenGoToMenu(client);
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	if(action & MenuAction_Cancel)
	{
		if(param2 == MenuCancel_Exit)
		{
			g_Setup[client][InZonesMenu] = false;
		}
	}
}

OpenSetFlagsMenu(client, Zone = -1, ZoneNumber = -1)
{
	g_Setup[client][InSetFlagsMenu] = true;
	g_Setup[client][ViewAnticheats] = true;

	new Handle:menu = CreateMenu(Menu_SetFlags);
	SetMenuExitBackButton(menu, true);

	if((Zone == -1 && ZoneNumber == -1) || !IsClientInsideZone(client, g_Zones[Zone][ZoneNumber]))
	{
		for(Zone = ANTICHEAT; Zone <= FREESTYLE; Zone++)
		{
			ZoneNumber = Timer_InsideZone(client, Zone);
		}
	}

	if(ZoneNumber != -1)
	{
		new String:ZoneNumberString[32];
		IntToString(ZoneNumber, ZoneNumberString, sizeof(ZoneNumberString));
		SetMenuTitle(menu, Zone == ANTICHEAT ? "Set Anti-cheat Zone flags [Zone %s]":"Set Freestyle Zone flags [Zone %s]", ZoneNumberString);

		decl String:sInfo[16];

		switch(Zone)
		{
			case ANTICHEAT:
			{
				FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", ANTICHEAT, ZoneNumber, FLAG_ANTICHEAT_MAIN);
				AddMenuItem(menu, sInfo, (g_Properties[Zone][Flags][ZoneNumber] & FLAG_ANTICHEAT_MAIN)?"Main: Yes":"Main: No");

				FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", ANTICHEAT, ZoneNumber, FLAG_ANTICHEAT_BONUS);
				AddMenuItem(menu, sInfo, (g_Properties[Zone][Flags][ZoneNumber] & FLAG_ANTICHEAT_BONUS)?"Bonus: Yes":"Bonus: No");

				DisplayMenu(menu, client, MENU_TIME_FOREVER);

				return;
			}
			case FREESTYLE:
			{
				decl String:sStyle[32], String:sDisplay[128];
				for(new Style; Style < MAX_STYLES; Style++)
				{
					if(Style_IsEnabled(Style) && Style_IsFreestyleAllowed(Style))
					{
						GetStyleName(Style, sStyle, sizeof(sStyle));

						FormatEx(sDisplay, sizeof(sDisplay), (g_Properties[Zone][Flags][ZoneNumber] & (1 << Style))?"%s: Yes":"%s: No", sStyle);

						FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", FREESTYLE, ZoneNumber, 1 << Style);

						AddMenuItem(menu, sInfo, sDisplay);
					}
				}

				DisplayMenu(menu, client, MENU_TIME_FOREVER);

				return;
			}
		}
	}
	else
	{
		SetMenuTitle(menu, "Not in Anti-cheat nor Freestyle zone");
		AddMenuItem(menu, "choose", "Go to a zone", ITEMDRAW_DISABLED);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}

public Menu_SetFlags(Handle:menu, MenuAction:action, client, param2)
{
	if(action == MenuAction_Select)
	{
		decl String:info[32];
		GetMenuItem(menu, param2, info, sizeof(info));

		if(StrEqual(info, "choose"))
		{
			OpenSetFlagsMenu(client);
		}
		else
		{
			decl String:sExplode[3][16];
			ExplodeString(info, ";", sExplode, 3, 16);

			new Zone       = StringToInt(sExplode[0]);
			new ZoneNumber = StringToInt(sExplode[1]);
			new flags      = StringToInt(sExplode[2]);

			SetZoneFlags(Zone, ZoneNumber, g_Properties[Zone][Flags][ZoneNumber] ^ flags);

			if(g_Properties[Zone][TriggerBased] == false){
				g_Setup[client][InSetFlagsMenu] = false;
				OpenZonesMenu(client);
			}else{
				OpenSetFlagsMenu(client, Zone, ZoneNumber);
			}
		}
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack)
			OpenGoToMenu(client);
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}

	if(action & MenuAction_Cancel)
	{
		if(param2 == MenuCancel_Exit)
		{
			g_Setup[client][InZonesMenu]    = false;
			g_Setup[client][InSetFlagsMenu] = false;
		}
		else if(param2 == MenuCancel_ExitBack)
		{
			g_Setup[client][InSetFlagsMenu] = false;

			OpenZonesMenu(client);
		}
	}
}

SetZoneFlags(Zone, ZoneNumber, flags)
{
	g_Properties[Zone][Flags][ZoneNumber] = flags;

	decl String:query[128];
	FormatEx(query, sizeof(query), "UPDATE zones SET flags = %d WHERE RowID = %d",
		g_Properties[Zone][Flags][ZoneNumber],
		g_Properties[Zone][RowID][ZoneNumber]);
	SQL_TQuery(g_DB, SetZoneFlags_Callback, query);
}

public SetZoneFlags_Callback(Handle:owner, Handle:hndl, String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError(error);
	}
}

bool:IsClientInsideZone(client, Float:point[8][3])
{
	new Float:fPos[3];
	Entity_GetAbsOrigin(client, fPos);

	// Add 5 units to a player's height or it won't work
	fPos[2] += 5.0;

	return IsPointInsideZone(fPos, point);
}

bool:IsPointInsideZone(Float:pos[3], Float:point[8][3])
{
	for(new i = 0; i < 3; i++)
	{
		if(point[0][i] >= pos[i] == point[7][i] >= pos[i])
		{
			return false;
		}
	}

	return true;
}

public Native_InsideZone(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	new Zone   = GetNativeCell(2);
	new flags  = GetNativeCell(3);

	for(new ZoneNumber; ZoneNumber < g_Properties[Zone][Count]; ZoneNumber++)
	{
		if(g_bInside[client][Zone][ZoneNumber] == true)
		{
			if(flags != -1)
			{
				if(g_Properties[Zone][Flags][ZoneNumber] & flags)
					return ZoneNumber;
			}
			else
			{
				return ZoneNumber;
			}
		}
	}

	return -1;
}

public Native_IsPointInsideZone(Handle:plugin, numParams)
{
	new Float:fPos[3];
	GetNativeArray(1, fPos, 3);

	new Zone       = GetNativeCell(2);
	new ZoneNumber = GetNativeCell(3);

	if(g_Properties[Zone][Ready][ZoneNumber] == true)
	{
		return IsPointInsideZone(fPos, g_Zones[Zone][ZoneNumber]);
	}
	else
	{
		return false;
	}
}

public Native_TeleportToZone(Handle:plugin, numParams)
{
	new client      = GetNativeCell(1);
	new Zone        = GetNativeCell(2);
	new ZoneNumber  = GetNativeCell(3);
	new bool:bottom = GetNativeCell(4);

	TeleportToZone(client, Zone, ZoneNumber, bottom);
}

public Native_GetTotalZonesAllMaps(Handle:plugin, numParams)
{
	return g_TotalZoneAllMaps[GetNativeCell(1)];
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon){
	if(IsPlayerAlive(client) && !IsFakeClient(client))
	{
		for(new Zone = 0; Zone < ZONE_COUNT; Zone++)
		{
			if(g_Properties[Zone][TriggerBased] == false)
			{
				for(new ZoneNumber = 0; ZoneNumber < g_Properties[Zone][Count]; ZoneNumber++)
				{
					g_bInside[client][Zone][ZoneNumber] = IsClientInsideZone(client, g_Zones[Zone][ZoneNumber]);

					if(g_bInside[client][Zone][ZoneNumber] == true)
					{
						switch(Zone)
						{
							case MAIN_START:
							{
								if(g_Properties[MAIN_END][Ready][0] == true)
									StartTimer(client, TIMER_MAIN);
							}
							case MAIN_END:
							{
								if(IsBeingTimed(client, TIMER_MAIN))
									FinishTimer(client);
							}
							case BONUS_START:
							{
								if(g_Properties[BONUS_END][Ready][0] == true)
									StartTimer(client, TIMER_BONUS);
							}
							case BONUS_END:
							{
								if(IsBeingTimed(client, TIMER_BONUS))
									FinishTimer(client);
							}
							case ANTICHEAT:
							{
								if(IsBeingTimed(client, TIMER_MAIN) && g_Properties[Zone][Flags][ZoneNumber] & FLAG_ANTICHEAT_MAIN)
								{
									StopTimer(client);

									PrintColorText(client, "%s%sYour timer was stopped for using a shortcut.",
										g_msg_start,
										g_msg_textcol);
								}

								if(IsBeingTimed(client, TIMER_BONUS) && g_Properties[Zone][Flags][ZoneNumber] & FLAG_ANTICHEAT_BONUS)
								{
									StopTimer(client);

									PrintColorText(client, "%s%sYour timer was stopped for using a shortcut.",
										g_msg_start,
										g_msg_textcol);
								}
								if(g_Setup[client][InSetFlagsMenu] == true)
									OpenSetFlagsMenu(client, Zone, ZoneNumber);
							}
							case FREESTYLE:
							{
								if(g_Setup[client][InSetFlagsMenu] == true)
									OpenSetFlagsMenu(client, Zone, ZoneNumber);
							}
						}
					}
				}
			}
		}
	}
}
