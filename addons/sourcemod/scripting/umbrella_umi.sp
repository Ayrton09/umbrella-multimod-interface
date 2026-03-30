#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <adminmenu>
#define REQUIRE_PLUGIN

#define PLUGIN_NAME "Umbrella Multimod Interface (UMI)"
#define PLUGIN_VERSION "1.0.0"
#define CHAT_PREFIX "{lightblue}[UMI] {default}"

public Plugin myinfo = {
    name = PLUGIN_NAME,
    author = "Ayrton09",
    description = "Advanced Multi-Mod Voting System (Ultimate Edition)",
    version = PLUGIN_VERSION
};

// --- Memoria ---
StringMap g_smGroupMaps;
ArrayList g_alGroupNames;
StringMap g_smMapToGroup;
StringMap g_smMapDisplay;
StringMap g_smMapWorkshopId;
StringMap g_smMapWorkshopMap;
StringMap g_smPlayerNoms;
ArrayList g_alMapHistory;
ArrayList g_alCurrentVoteOptions;
char g_sAdminSelectedMap[MAXPLAYERS + 1][64];

// --- Estado ---
bool g_bVoteActive = false;
bool g_bChangeOnRoundEnd = false;
bool g_bMapChangeScheduled = false;
bool g_bPhase1TieBreakActive = false;
bool g_bPhase2TieBreakActive = false;
int g_iPhase1TieBreakRounds = 0;
int g_iPhase2TieBreakRounds = 0;
Handle g_hPhase2Timer = null;
Handle g_hMapJumpTimer = null;
int g_iVotesRTV = 0;
bool g_bPlayerRTVd[MAXPLAYERS + 1];
char g_sWinningGroup[64];
char g_sNextMap[64];
char g_sNextMapTarget[64];
char g_sNextWorkshopId[32];
bool g_bNextMapIsWorkshop = false;
char g_sPrevNextMap[64];
bool g_bHasPrevNextMap = false;
int g_iExtendCount = 0;
int g_iTriggerType = 0;
float g_fMapStartTime = 0.0;
bool g_bAutoVoteFired = false;
EngineVersion g_GameEngine;

// --- Admin Menu ---
TopMenu g_hTopMenu;

// --- ConVars ---
ConVar g_cvRTVRatio, g_cvVoteTime, g_cvActionRTV, g_cvActionAuto, g_cvHistory, g_cvExtTime, g_cvMaxExt, g_cvMaxMaps, g_cvRTVDelay, g_cvTieBreakEnable, g_cvSoundStart, g_cvSoundWin;
ConVar g_cvTieBreakTime, g_cvTieBreakMaxRounds, g_cvTieBreakAnnounce, g_cvTieBreakSound, g_cvDebug, g_cvStrictMapValidation;

public void OnPluginStart() {
    LoadTranslations("umi_multimod.phrases");
    g_GameEngine = GetEngineVersion();

    g_smGroupMaps = new StringMap();
    g_alGroupNames = new ArrayList(ByteCountToCells(64));
    g_smMapToGroup = new StringMap();
    g_smMapDisplay = new StringMap();
    g_smMapWorkshopId = new StringMap();
    g_smMapWorkshopMap = new StringMap();
    g_smPlayerNoms = new StringMap();
    g_alMapHistory = new ArrayList(ByteCountToCells(64));
    g_alCurrentVoteOptions = new ArrayList(ByteCountToCells(64));

    RegConsoleCmd("sm_nominate", Cmd_Nominate);
    RegConsoleCmd("sm_rtv", Cmd_RTV);

    AddCommandListener(Listener_Chat, "say");
    AddCommandListener(Listener_Chat, "say_team");

    if (g_GameEngine == Engine_TF2) {
        HookEventEx("teamplay_round_win", Event_RoundEnd, EventHookMode_PostNoCopy);
    } else {
        HookEventEx("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
        if (g_GameEngine == Engine_CSGO) {
            HookEventEx("cs_win_panel_match", Event_RoundEnd, EventHookMode_PostNoCopy);
        }
    }

    g_cvRTVRatio = CreateConVar("umi_rtv_ratio", "0.5", "RTV ratio required to pass (0.5 = 50%% of real players). Recommended: 0.50-0.66.", _, true, 0.05, true, 1.0);
    g_cvVoteTime = CreateConVar("umi_vote_start_time", "3.0", "Auto-vote trigger time in minutes before map end. 0 disables the time-based trigger.", _, true, 0.0, true, 60.0);
    g_cvActionRTV = CreateConVar("umi_action_rtv", "1", "Map change behavior after RTV vote win. 0 = instant change, 1 = change at round end.", _, true, 0.0, true, 1.0);
    g_cvActionAuto = CreateConVar("umi_action_auto", "1", "Map change behavior after auto vote win. 0 = instant change, 1 = change at round end.", _, true, 0.0, true, 1.0);
    g_cvHistory = CreateConVar("umi_history_size", "10", "Recent map history size excluded from nominations and phase 2 options. 0 disables history exclusion.", _, true, 0.0, true, 100.0);
    g_cvExtTime = CreateConVar("umi_extend_time", "15", "Minutes added when Extend Map wins or admin forces an extension.", _, true, 1.0, true, 180.0);
    g_cvMaxExt = CreateConVar("umi_extend_limit", "2", "Max number of extensions allowed per map. 0 disables Extend Map option.", _, true, 0.0, true, 20.0);
    g_cvMaxMaps = CreateConVar("umi_max_options", "6", "Max map options shown in phase 2 vote (filled with nominations first, then random maps).", _, true, 2.0, true, 10.0);
    g_cvRTVDelay = CreateConVar("umi_rtv_delay", "2.0", "Minutes after map start before players can use !rtv.", _, true, 0.0, true, 60.0);
    g_cvTieBreakEnable = CreateConVar("umi_tiebreak_enable", "1", "Tie-break support for first-place ties. 0 = disabled (random fallback), 1 = enabled.", _, true, 0.0, true, 1.0);
    g_cvTieBreakTime = CreateConVar("umi_tiebreak_time", "15", "Tie-break vote duration in seconds.", _, true, 5.0, true, 60.0);
    g_cvTieBreakMaxRounds = CreateConVar("umi_tiebreak_max_rounds", "1", "Maximum tie-break rounds before forced random fallback. 0 = no tie-break rounds.", _, true, 0.0, true, 5.0);
    g_cvTieBreakAnnounce = CreateConVar("umi_tiebreak_announce", "1", "Announce tie-break and random tie fallback in chat. 0 = no, 1 = yes.", _, true, 0.0, true, 1.0);
    g_cvTieBreakSound = CreateConVar("umi_tiebreak_sound", "", "Tie-break start sound path. Leave empty to reuse umi_sound_start.");
    g_cvDebug = CreateConVar("umi_debug", "0", "Verbose debug logs in server console/logs. 0 = disabled, 1 = enabled.", _, true, 0.0, true, 1.0);
    g_cvStrictMapValidation = CreateConVar("umi_strict_map_validation", "0", "Strict map validation for mapcycle and nominations. 0 = soft (allow even if IsMapValid fails), 1 = strict.", _, true, 0.0, true, 1.0);
    g_cvSoundStart = CreateConVar("umi_sound_start", "ui/beep07.wav", "Sound path played when votes start (phase 1, phase 2, or fallback tie-break).");
    g_cvSoundWin = CreateConVar("umi_sound_win", "ui/achievement_earned.wav", "Sound path played when a map winner is decided.");

    AutoExecConfig(true, "umbrella_multimod_interface");

    TopMenu topmenu;
    if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null)) {
        OnAdminMenuReady(topmenu);
    }
}

public void OnLibraryRemoved(const char[] name) {
    if (StrEqual(name, "adminmenu")) {
        g_hTopMenu = null;
    }
}

public void OnAdminMenuReady(Handle aTopMenu) {
    TopMenu topmenu = TopMenu.FromHandle(aTopMenu);
    if (g_hTopMenu == topmenu) {
        return;
    }

    g_hTopMenu = topmenu;

    TopMenuObject obj_umi = g_hTopMenu.AddCategory("umi_menu", AdminMenu_UMI, "sm_umi_menu", ADMFLAG_CHANGEMAP);
    if (obj_umi != INVALID_TOPMENUOBJECT) {
        g_hTopMenu.AddItem("umi_force", AdminMenu_UMI_Items, obj_umi, "sm_umi_force", ADMFLAG_CHANGEMAP);
        g_hTopMenu.AddItem("umi_setnext", AdminMenu_UMI_Items, obj_umi, "sm_umi_setnext", ADMFLAG_CHANGEMAP);
        g_hTopMenu.AddItem("umi_cancel", AdminMenu_UMI_Items, obj_umi, "sm_umi_cancel", ADMFLAG_CHANGEMAP);
        g_hTopMenu.AddItem("umi_extend", AdminMenu_UMI_Items, obj_umi, "sm_umi_extend", ADMFLAG_CHANGEMAP);
        g_hTopMenu.AddItem("umi_abort", AdminMenu_UMI_Items, obj_umi, "sm_umi_abort", ADMFLAG_CHANGEMAP);
        g_hTopMenu.AddItem("umi_reload", AdminMenu_UMI_Items, obj_umi, "sm_umi_reload", ADMFLAG_CONFIG);
    }
}

public void AdminMenu_UMI(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
    if (action == TopMenuAction_DisplayTitle || action == TopMenuAction_DisplayOption) {
        Format(buffer, maxlength, "%T", "Admin_Menu_Title", param);
    }
}

public void AdminMenu_UMI_Items(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
    if (action == TopMenuAction_DisplayOption) {
        char name[64];
        topmenu.GetObjName(object_id, name, sizeof(name));

        if (StrEqual(name, "umi_force")) {
            Format(buffer, maxlength, "%T", "Admin_Menu_Force", param);
        } else if (StrEqual(name, "umi_setnext")) {
            Format(buffer, maxlength, "%T", "Admin_Menu_SetNext", param);
        } else if (StrEqual(name, "umi_cancel")) {
            Format(buffer, maxlength, "%T", "Admin_Menu_Cancel", param);
        } else if (StrEqual(name, "umi_extend")) {
            Format(buffer, maxlength, "%T", "Admin_Menu_Extend", param, g_cvExtTime.IntValue);
        } else if (StrEqual(name, "umi_abort")) {
            Format(buffer, maxlength, "%T", "Admin_Menu_AbortNext", param);
        } else if (StrEqual(name, "umi_reload")) {
            Format(buffer, maxlength, "%T", "Admin_Menu_Reload", param);
        }
    } else if (action == TopMenuAction_SelectOption) {
        char name[64];
        topmenu.GetObjName(object_id, name, sizeof(name));

        if (StrEqual(name, "umi_force")) {
            if (g_bVoteActive) {
                CPrintToChat(param, "%s%T", CHAT_PREFIX, "Admin_Error_VoteActive", param);
            } else {
                StartPhase1(3);
            }
        } else if (StrEqual(name, "umi_setnext")) {
            ShowAdminSetNextGroupMenu(param);
        } else if (StrEqual(name, "umi_cancel")) {
            if (g_bVoteActive) {
                if (IsVoteInProgress()) {
                    CancelVote();
                }
                ResetVoteFlowState();
                for (int i = 1; i <= MaxClients; i++) {
                    if (IsClientInGame(i) && !IsFakeClient(i)) {
                        CPrintToChat(i, "%s%T", CHAT_PREFIX, "Admin_Action_Canceled", i);
                    }
                }
            } else {
                CPrintToChat(param, "%s%T", CHAT_PREFIX, "Admin_Error_NoVote", param);
            }
        } else if (StrEqual(name, "umi_extend")) {
            ExtendMapTimeLimit(g_cvExtTime.IntValue * 60);
            g_bAutoVoteFired = false;
            for (int i = 1; i <= MaxClients; i++) {
                if (IsClientInGame(i) && !IsFakeClient(i)) {
                    CPrintToChat(i, "%s%T", CHAT_PREFIX, "Admin_Action_Extended", i, g_cvExtTime.IntValue);
                }
            }
        } else if (StrEqual(name, "umi_abort")) {
            if (g_bChangeOnRoundEnd || !StrEqual(g_sNextMap, "")) {
                ResetVoteFlowState();
                CancelScheduledMapJump();
                ClearNextMapSelection();
                RestorePreviousNextMap();
                for (int i = 1; i <= MaxClients; i++) {
                    if (IsClientInGame(i) && !IsFakeClient(i)) {
                        CPrintToChat(i, "%s%T", CHAT_PREFIX, "Admin_Action_Aborted", i);
                    }
                }
            } else {
                CPrintToChat(param, "%s%T", CHAT_PREFIX, "Admin_Error_NoNextMap", param);
            }
        } else if (StrEqual(name, "umi_reload")) {
            ClearCache();
            ParseCycle();
            CPrintToChat(param, "%s%T", CHAT_PREFIX, "Admin_Action_Reloaded", param);
        }
    }
}

void PrepareSounds() {
    char sS[64], sW[64], sT[64], fP[PLATFORM_MAX_PATH];
    g_cvSoundStart.GetString(sS, sizeof(sS));
    g_cvSoundWin.GetString(sW, sizeof(sW));
    g_cvTieBreakSound.GetString(sT, sizeof(sT));

    if (sS[0] != '\0') {
        PrecacheSound(sS, true);
        Format(fP, sizeof(fP), "sound/%s", sS);
        if (FileExists(fP)) {
            AddFileToDownloadsTable(fP);
        }
    }

    if (sW[0] != '\0') {
        PrecacheSound(sW, true);
        Format(fP, sizeof(fP), "sound/%s", sW);
        if (FileExists(fP)) {
            AddFileToDownloadsTable(fP);
        }
    }

    if (sT[0] != '\0') {
        PrecacheSound(sT, true);
        Format(fP, sizeof(fP), "sound/%s", sT);
        if (FileExists(fP)) {
            AddFileToDownloadsTable(fP);
        }
    }
}

void PlayVoteSound(int type) {
    char s[64];
    if (type == 1) {
        g_cvSoundStart.GetString(s, sizeof(s));
    } else {
        g_cvSoundWin.GetString(s, sizeof(s));
    }

    if (s[0] != '\0') {
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                EmitSoundToClient(i, s);
            }
        }
    }
}

void PlayTieBreakSound() {
    char s[64];
    g_cvTieBreakSound.GetString(s, sizeof(s));
    if (s[0] == '\0') {
        PlayVoteSound(1);
        return;
    }

    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            EmitSoundToClient(i, s);
        }
    }
}

void DebugLog(const char[] fmt, any ...) {
    if (!g_cvDebug.BoolValue) {
        return;
    }

    char buffer[256];
    VFormat(buffer, sizeof(buffer), fmt, 2);
    LogMessage("UMI DEBUG: %s", buffer);
}

void CapturePreviousNextMap() {
    if (g_bHasPrevNextMap) {
        return;
    }

    char previous[64];
    if (!GetNextMap(previous, sizeof(previous)) || previous[0] == '\0') {
        GetCurrentMap(previous, sizeof(previous));
    }

    strcopy(g_sPrevNextMap, sizeof(g_sPrevNextMap), previous);
    g_bHasPrevNextMap = true;
    DebugLog("Captured previous nextmap: '%s'.", g_sPrevNextMap);
}

void ClearPreviousNextMap() {
    g_bHasPrevNextMap = false;
    g_sPrevNextMap[0] = '\0';
}

void RestorePreviousNextMap() {
    if (!g_bHasPrevNextMap) {
        return;
    }

    if (!SetNextMap(g_sPrevNextMap)) {
        LogError("UMI: Failed to restore previous nextmap '%s'.", g_sPrevNextMap);
    } else {
        DebugLog("Restored previous nextmap: '%s'.", g_sPrevNextMap);
    }
    ClearPreviousNextMap();
}

public void OnMapStart() {
    ClearCache();
    ParseCycle();
    PrepareSounds();

    g_bVoteActive = false;
    g_bChangeOnRoundEnd = false;
    g_bMapChangeScheduled = false;
    g_hPhase2Timer = null;
    g_hMapJumpTimer = null;
    g_bPhase1TieBreakActive = false;
    g_bPhase2TieBreakActive = false;
    g_iPhase1TieBreakRounds = 0;
    g_iPhase2TieBreakRounds = 0;
    ClearPreviousNextMap();
    g_iVotesRTV = 0;
    g_iExtendCount = 0;
    g_bAutoVoteFired = false;
    g_fMapStartTime = GetGameTime();

    for (int i = 1; i <= MaxClients; i++) {
        g_bPlayerRTVd[i] = false;
    }

    ClearNextMapSelection();
    strcopy(g_sWinningGroup, sizeof(g_sWinningGroup), "");

    char currentMap[64];
    GetCurrentMap(currentMap, sizeof(currentMap));
    g_alMapHistory.PushString(currentMap);
    if (g_alMapHistory.Length > g_cvHistory.IntValue) {
        g_alMapHistory.Erase(0);
    }

    CreateTimer(10.0, Timer_CheckTime, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void ClearCache() {
    StringMapSnapshot snap = g_smGroupMaps.Snapshot();
    for (int i = 0; i < snap.Length; i++) {
        char k[64];
        snap.GetKey(i, k, sizeof(k));
        ArrayList al;
        g_smGroupMaps.GetValue(k, al);
        delete al;
    }
    delete snap;

    g_smGroupMaps.Clear();
    g_alGroupNames.Clear();
    g_smMapToGroup.Clear();
    g_smMapDisplay.Clear();
    g_smMapWorkshopId.Clear();
    g_smMapWorkshopMap.Clear();
    g_smPlayerNoms.Clear();
}

bool IsNumericString(const char[] text) {
    if (text[0] == '\0') {
        return false;
    }

    for (int i = 0; text[i] != '\0'; i++) {
        if (text[i] < '0' || text[i] > '9') {
            return false;
        }
    }
    return true;
}

void GetMapEntryDisplayName(const char[] mapEntry, char[] display, int maxlen) {
    if (!g_smMapDisplay.GetString(mapEntry, display, maxlen)) {
        strcopy(display, maxlen, mapEntry);
    }
}

bool GetWorkshopInfoForEntry(const char[] mapEntry, char[] workshopId, int workshopIdLen, char[] workshopMap, int workshopMapLen) {
    workshopMap[0] = '\0';
    if (!g_smMapWorkshopId.GetString(mapEntry, workshopId, workshopIdLen)) {
        return false;
    }

    g_smMapWorkshopMap.GetString(mapEntry, workshopMap, workshopMapLen);
    return true;
}

bool IsMapEntryInHistory(const char[] mapEntry) {
    if (IsInHistory(mapEntry)) {
        return true;
    }

    char workshopMap[64];
    if (g_smMapWorkshopMap.GetString(mapEntry, workshopMap, sizeof(workshopMap)) && workshopMap[0] != '\0') {
        if (IsInHistory(workshopMap)) {
            return true;
        }
    }

    return false;
}

void ClearNextMapSelection() {
    g_sNextMap[0] = '\0';
    g_sNextMapTarget[0] = '\0';
    g_sNextWorkshopId[0] = '\0';
    g_bNextMapIsWorkshop = false;
}

void SetNextMapSelection(const char[] mapEntry) {
    char display[64], workshopId[32], workshopMap[64];
    GetMapEntryDisplayName(mapEntry, display, sizeof(display));
    strcopy(g_sNextMap, sizeof(g_sNextMap), display);

    g_bNextMapIsWorkshop = GetWorkshopInfoForEntry(mapEntry, workshopId, sizeof(workshopId), workshopMap, sizeof(workshopMap));
    if (g_bNextMapIsWorkshop) {
        strcopy(g_sNextWorkshopId, sizeof(g_sNextWorkshopId), workshopId);
        if (workshopMap[0] != '\0') {
            strcopy(g_sNextMapTarget, sizeof(g_sNextMapTarget), workshopMap);
        } else {
            g_sNextMapTarget[0] = '\0';
        }
        return;
    }

    g_sNextWorkshopId[0] = '\0';
    strcopy(g_sNextMapTarget, sizeof(g_sNextMapTarget), mapEntry);
}

bool TryChangeToWorkshopMap(const char[] workshopId, const char[] fallbackMap) {
    if (workshopId[0] == '\0') {
        return false;
    }

    if (CommandExists("ds_workshop_changelevel")) {
        ServerCommand("ds_workshop_changelevel %s", workshopId);
        ServerExecute();
        DebugLog("Workshop change using ds_workshop_changelevel %s.", workshopId);
        return true;
    }

    if (CommandExists("host_workshop_map")) {
        ServerCommand("host_workshop_map %s", workshopId);
        ServerExecute();
        DebugLog("Workshop change using host_workshop_map %s.", workshopId);
        return true;
    }

    if (CommandExists("workshop_changelevel")) {
        ServerCommand("workshop_changelevel %s", workshopId);
        ServerExecute();
        DebugLog("Workshop change using workshop_changelevel %s.", workshopId);
        return true;
    }

    if (fallbackMap[0] != '\0') {
        DebugLog("Workshop command unavailable; using fallback map '%s'.", fallbackMap);
        ForceChangeLevel(fallbackMap, "UMI Workshop Fallback");
        return true;
    }

    LogError("UMI: No workshop change command found for workshop id '%s'.", workshopId);
    return false;
}

void ParseCycle() {
    KeyValues kv = new KeyValues("umi_mapcycle");
    char p[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, p, sizeof(p), "configs/umi_mapcycle.txt");
    if (!kv.ImportFromFile(p)) {
        LogError("UMI: Could not load mapcycle file: %s", p);
        delete kv;
        return;
    }

    int loadedGroups = 0;
    int loadedMaps = 0;
    if (kv.GotoFirstSubKey()) {
        do {
            char g[64];
            kv.GetSectionName(g, sizeof(g));

            ArrayList al = new ArrayList(ByteCountToCells(64));
            int invalidCount = 0;
            if (kv.GotoFirstSubKey()) {
                do {
                    char m[64];
                    kv.GetSectionName(m, sizeof(m));

                    char display[64], workshopId[32], workshopMap[64];
                    kv.GetString("display", display, sizeof(display), m);
                    kv.GetString("workshop_id", workshopId, sizeof(workshopId), "");
                    kv.GetString("map", workshopMap, sizeof(workshopMap), "");

                    if (workshopId[0] == '\0' && IsNumericString(m)) {
                        strcopy(workshopId, sizeof(workshopId), m);
                    }

                    bool isWorkshop = (workshopId[0] != '\0');
                    if (isWorkshop && !IsNumericString(workshopId)) {
                        invalidCount++;
                        LogError("UMI: Invalid workshop id '%s' in group '%s' (entry '%s' ignored).", workshopId, g, m);
                        continue;
                    }

                    if (!isWorkshop) {
                        bool valid = IsMapValid(m);
                        if (g_cvStrictMapValidation.BoolValue && !valid) {
                            invalidCount++;
                            LogError("UMI: Invalid map '%s' in group '%s' (ignored).", m, g);
                            continue;
                        }
                        if (!valid) {
                            DebugLog("Map '%s' in group '%s' is not validated by IsMapValid, but is allowed in soft mode.", m, g);
                        }
                    } else {
                        if (workshopMap[0] != '\0' && !IsMapValid(workshopMap)) {
                            DebugLog("Workshop entry '%s' (%s) has map fallback '%s' not validated yet.", m, workshopId, workshopMap);
                        }
                    }

                    al.PushString(m);
                    g_smMapToGroup.SetString(m, g);
                    if (!StrEqual(display, m, false)) {
                        g_smMapDisplay.SetString(m, display);
                    }
                    if (isWorkshop) {
                        g_smMapWorkshopId.SetString(m, workshopId);
                        if (workshopMap[0] != '\0') {
                            g_smMapWorkshopMap.SetString(m, workshopMap);
                        }
                    }
                    loadedMaps++;
                } while (kv.GotoNextKey());
                kv.GoBack();
            }

            if (al.Length > 0) {
                g_alGroupNames.PushString(g);
                g_smGroupMaps.SetValue(g, al);
                loadedGroups++;
                DebugLog("Loaded group '%s' with %d maps.", g, al.Length);
            } else {
                LogError("UMI: Group '%s' has no valid maps and was excluded (invalid: %d).", g, invalidCount);
                delete al;
            }
        } while (kv.GotoNextKey());
    }

    DebugLog("ParseCycle complete: %d groups, %d maps.", loadedGroups, loadedMaps);
    delete kv;
}

bool IsValidHumanClient(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

public void OnClientPutInServer(int client) {
    if (client <= 0 || client > MaxClients) {
        return;
    }

    g_bPlayerRTVd[client] = false;
    g_sAdminSelectedMap[client][0] = '\0';
}

public void OnClientDisconnect(int client) {
    if (client <= 0 || client > MaxClients) {
        return;
    }

    if (g_bPlayerRTVd[client]) {
        g_bPlayerRTVd[client] = false;
        if (g_iVotesRTV > 0) {
            g_iVotesRTV--;
        }
        DebugLog("Client %d disconnected; RTV progress adjusted to %d.", client, g_iVotesRTV);
    }

    g_sAdminSelectedMap[client][0] = '\0';
}

void ResetRTVState() {
    g_iVotesRTV = 0;
    for (int i = 1; i <= MaxClients; i++) {
        g_bPlayerRTVd[i] = false;
    }
}

void CancelPhase2Transition() {
    if (g_hPhase2Timer != null) {
        delete g_hPhase2Timer;
        g_hPhase2Timer = null;
    }
}

void CancelScheduledMapJump() {
    if (g_hMapJumpTimer != null) {
        delete g_hMapJumpTimer;
        g_hMapJumpTimer = null;
    }
    g_bMapChangeScheduled = false;
}

void ResetVoteFlowState() {
    g_bVoteActive = false;
    g_bChangeOnRoundEnd = false;
    g_bPhase1TieBreakActive = false;
    g_bPhase2TieBreakActive = false;
    g_iPhase1TieBreakRounds = 0;
    g_iPhase2TieBreakRounds = 0;
    strcopy(g_sWinningGroup, sizeof(g_sWinningGroup), "");
    CancelPhase2Transition();
    ResetRTVState();
}

void ResolvePhase1Winner(const char[] win) {
    g_bPhase1TieBreakActive = false;
    g_iPhase1TieBreakRounds = 0;

    if (StrEqual(win, "@ext")) {
        ExtendMapTimeLimit(g_cvExtTime.IntValue * 60);
        g_iExtendCount++;
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                CPrintToChat(i, "%s%T", CHAT_PREFIX, "Vote_Extended", i, g_cvExtTime.IntValue);
            }
        }
        g_bAutoVoteFired = false;
        ResetVoteFlowState();
        return;
    }

    strcopy(g_sWinningGroup, sizeof(g_sWinningGroup), win);
    CancelPhase2Transition();
    g_hPhase2Timer = CreateTimer(1.0, Timer_Phase2);
}

void ResolvePhase2Winner(const char[] win) {
    g_bPhase2TieBreakActive = false;
    g_iPhase2TieBreakRounds = 0;
    ProcessPhase2Win(win);
}

void StartTieBreakPhase1(Menu sourceMenu, int itemIndexA, int itemIndexB) {
    char infoA[64], infoB[64], displayA[128], displayB[128];
    sourceMenu.GetItem(itemIndexA, infoA, sizeof(infoA), _, displayA, sizeof(displayA));
    sourceMenu.GetItem(itemIndexB, infoB, sizeof(infoB), _, displayB, sizeof(displayB));

    Menu tieMenu = new Menu(H_Phase1);
    tieMenu.VoteResultCallback = VCB_Phase1;

    char title[128];
    Format(title, sizeof(title), "%T", "Menu_Title_Tiebreak_Phase1", LANG_SERVER);
    tieMenu.SetTitle(title);
    tieMenu.AddItem(infoA, displayA);
    tieMenu.AddItem(infoB, displayB);
    tieMenu.ExitButton = false;

    g_bPhase1TieBreakActive = true;
    if (g_cvTieBreakAnnounce.BoolValue) {
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                CPrintToChat(i, "%s%T", CHAT_PREFIX, "Vote_Tie_Detected", i, displayA, displayB);
            }
        }
    }
    DebugLog("Phase1 tie-break started between '%s' and '%s' (round %d).", infoA, infoB, g_iPhase1TieBreakRounds);
    PlayTieBreakSound();
    if (!tieMenu.DisplayVoteToAll(g_cvTieBreakTime.IntValue)) {
        LogError("UMI: Failed to display phase 1 tie-break vote.");
        g_bPhase1TieBreakActive = false;
        char fallback[64];
        strcopy(fallback, sizeof(fallback), (GetRandomInt(0, 1) == 0) ? infoA : infoB);
        if (g_cvTieBreakAnnounce.BoolValue) {
            for (int i = 1; i <= MaxClients; i++) {
                if (IsClientInGame(i) && !IsFakeClient(i)) {
                    CPrintToChat(i, "%s%T", CHAT_PREFIX, "Vote_Tie_Fallback_Random", i, fallback);
                }
            }
        }
        DebugLog("Phase1 tie-break display failed. Random fallback winner: '%s'.", fallback);
        ResolvePhase1Winner(fallback);
        delete tieMenu;
    }
}

void StartTieBreakPhase2(Menu sourceMenu, int itemIndexA, int itemIndexB) {
    char infoA[64], infoB[64], displayA[128], displayB[128];
    sourceMenu.GetItem(itemIndexA, infoA, sizeof(infoA), _, displayA, sizeof(displayA));
    sourceMenu.GetItem(itemIndexB, infoB, sizeof(infoB), _, displayB, sizeof(displayB));

    Menu tieMenu = new Menu(H_Phase2);
    tieMenu.VoteResultCallback = VCB_Phase2;

    char title[160];
    Format(title, sizeof(title), "%T", "Menu_Title_Tiebreak_Phase2", LANG_SERVER, g_sWinningGroup);
    tieMenu.SetTitle(title);
    tieMenu.AddItem(infoA, displayA);
    tieMenu.AddItem(infoB, displayB);
    tieMenu.ExitButton = false;

    g_bPhase2TieBreakActive = true;
    if (g_cvTieBreakAnnounce.BoolValue) {
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                CPrintToChat(i, "%s%T", CHAT_PREFIX, "Vote_Tie_Detected", i, displayA, displayB);
            }
        }
    }
    DebugLog("Phase2 tie-break started in group '%s' between '%s' and '%s' (round %d).", g_sWinningGroup, infoA, infoB, g_iPhase2TieBreakRounds);
    PlayTieBreakSound();
    if (!tieMenu.DisplayVoteToAll(g_cvTieBreakTime.IntValue)) {
        LogError("UMI: Failed to display phase 2 tie-break vote.");
        g_bPhase2TieBreakActive = false;
        char fallback[64];
        strcopy(fallback, sizeof(fallback), (GetRandomInt(0, 1) == 0) ? infoA : infoB);
        if (g_cvTieBreakAnnounce.BoolValue) {
            for (int i = 1; i <= MaxClients; i++) {
                if (IsClientInGame(i) && !IsFakeClient(i)) {
                    CPrintToChat(i, "%s%T", CHAT_PREFIX, "Vote_Tie_Fallback_Random", i, fallback);
                }
            }
        }
        DebugLog("Phase2 tie-break display failed. Random fallback winner: '%s'.", fallback);
        ResolvePhase2Winner(fallback);
        delete tieMenu;
    }
}

public void VCB_Phase1(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info) {
    if (num_items <= 0) {
        return;
    }

    int topVotes = item_info[0][VOTEINFO_ITEM_VOTES];
    int tiedCount = 0;
    while (tiedCount < num_items && item_info[tiedCount][VOTEINFO_ITEM_VOTES] == topVotes) {
        tiedCount++;
    }

    if (tiedCount >= 2) {
        if (g_cvTieBreakEnable.BoolValue && g_iPhase1TieBreakRounds < g_cvTieBreakMaxRounds.IntValue) {
            g_iPhase1TieBreakRounds++;
            StartTieBreakPhase1(menu, item_info[0][VOTEINFO_ITEM_INDEX], item_info[1][VOTEINFO_ITEM_INDEX]);
            return;
        }

        int pick = GetRandomInt(0, tiedCount - 1);
        int winIndex = item_info[pick][VOTEINFO_ITEM_INDEX];
        char win[64];
        menu.GetItem(winIndex, win, sizeof(win));
        if (g_cvTieBreakAnnounce.BoolValue) {
            for (int i = 1; i <= MaxClients; i++) {
                if (IsClientInGame(i) && !IsFakeClient(i)) {
                    CPrintToChat(i, "%s%T", CHAT_PREFIX, "Vote_Tie_Fallback_Random", i, win);
                }
            }
        }
        DebugLog("Phase1 tie fallback picked '%s' (tied=%d, rounds=%d, enabled=%d).", win, tiedCount, g_iPhase1TieBreakRounds, g_cvTieBreakEnable.IntValue);
        ResolvePhase1Winner(win);
        return;
    }

    char winner[64];
    menu.GetItem(item_info[0][VOTEINFO_ITEM_INDEX], winner, sizeof(winner));
    DebugLog("Phase1 winner resolved: '%s' (votes=%d/%d).", winner, topVotes, num_votes);
    ResolvePhase1Winner(winner);
}

public void VCB_Phase2(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info) {
    if (num_items <= 0) {
        return;
    }

    int topVotes = item_info[0][VOTEINFO_ITEM_VOTES];
    int tiedCount = 0;
    while (tiedCount < num_items && item_info[tiedCount][VOTEINFO_ITEM_VOTES] == topVotes) {
        tiedCount++;
    }

    if (tiedCount >= 2) {
        if (g_cvTieBreakEnable.BoolValue && g_iPhase2TieBreakRounds < g_cvTieBreakMaxRounds.IntValue) {
            g_iPhase2TieBreakRounds++;
            StartTieBreakPhase2(menu, item_info[0][VOTEINFO_ITEM_INDEX], item_info[1][VOTEINFO_ITEM_INDEX]);
            return;
        }

        int pick = GetRandomInt(0, tiedCount - 1);
        int winIndex = item_info[pick][VOTEINFO_ITEM_INDEX];
        char win[64];
        char winDisplay[64];
        menu.GetItem(winIndex, win, sizeof(win));
        GetMapEntryDisplayName(win, winDisplay, sizeof(winDisplay));
        if (g_cvTieBreakAnnounce.BoolValue) {
            for (int i = 1; i <= MaxClients; i++) {
                if (IsClientInGame(i) && !IsFakeClient(i)) {
                    CPrintToChat(i, "%s%T", CHAT_PREFIX, "Vote_Tie_Fallback_Random", i, winDisplay);
                }
            }
        }
        DebugLog("Phase2 tie fallback picked '%s' (group='%s', tied=%d, rounds=%d, enabled=%d).", winDisplay, g_sWinningGroup, tiedCount, g_iPhase2TieBreakRounds, g_cvTieBreakEnable.IntValue);
        ResolvePhase2Winner(win);
        return;
    }

    char winner[64];
    menu.GetItem(item_info[0][VOTEINFO_ITEM_INDEX], winner, sizeof(winner));
    DebugLog("Phase2 winner resolved: '%s' (votes=%d/%d).", winner, topVotes, num_votes);
    ResolvePhase2Winner(winner);
}

void ScheduleMapJump(float delay) {
    if (g_bMapChangeScheduled || StrEqual(g_sNextMap, "")) {
        DebugLog("ScheduleMapJump ignored (scheduled=%d, nextmap='%s').", g_bMapChangeScheduled, g_sNextMap);
        return;
    }

    g_bMapChangeScheduled = true;
    DebugLog("Scheduling map jump to '%s' in %.1f seconds.", g_sNextMap, delay);
    g_hMapJumpTimer = CreateTimer(delay, Timer_Jump);
}

// --- FASE 1: CATEGORIA ---
bool StartPhase1(int trigger) {
    if (g_bVoteActive) {
        return false;
    }

    if (g_alGroupNames.Length == 0) {
        LogError("UMI: StartPhase1 aborted because no map groups were loaded.");
        return false;
    }

    g_bVoteActive = true;
    g_bPhase1TieBreakActive = false;
    g_bPhase2TieBreakActive = false;
    g_iPhase1TieBreakRounds = 0;
    g_iPhase2TieBreakRounds = 0;
    g_iTriggerType = trigger;
    PlayVoteSound(1);

    Menu menu = new Menu(H_Phase1);
    menu.VoteResultCallback = VCB_Phase1;
    char title[128];
    Format(title, sizeof(title), "%T", "Menu_Title_Phase1", LANG_SERVER);
    menu.SetTitle(title);

    if (g_iExtendCount < g_cvMaxExt.IntValue) {
        char extText[64];
        Format(extText, sizeof(extText), "%T", "Extend_Map", LANG_SERVER);
        menu.AddItem("@ext", extText);
    }

    for (int i = 0; i < g_alGroupNames.Length; i++) {
        char n[64];
        g_alGroupNames.GetString(i, n, sizeof(n));
        menu.AddItem(n, n);
    }

    menu.ExitButton = false;
    if (!menu.DisplayVoteToAll(20)) {
        LogError("UMI: Failed to display phase 1 vote.");
        ResetVoteFlowState();
        delete menu;
        return false;
    }
    return true;
}

public int H_Phase1(Menu menu, MenuAction action, int p1, int p2) {
    if (action == MenuAction_VoteEnd) {
        char win[64];
        menu.GetItem(p1, win, sizeof(win));
        ResolvePhase1Winner(win);
    } else if (action == MenuAction_VoteCancel && p1 == VoteCancel_NoVotes) {
        char win[64];
        if (g_bPhase1TieBreakActive && menu.ItemCount > 0) {
            int randomItem = GetRandomInt(0, menu.ItemCount - 1);
            menu.GetItem(randomItem, win, sizeof(win));
            ResolvePhase1Winner(win);
        } else if (g_alGroupNames.Length > 0) {
            g_alGroupNames.GetString(GetRandomInt(0, g_alGroupNames.Length - 1), win, sizeof(win));
            strcopy(g_sWinningGroup, sizeof(g_sWinningGroup), win);
            for (int i = 1; i <= MaxClients; i++) {
                if (IsClientInGame(i) && !IsFakeClient(i)) {
                    CPrintToChat(i, "%s%T", CHAT_PREFIX, "No_Votes_Category", i);
                }
            }
            CancelPhase2Transition();
            g_hPhase2Timer = CreateTimer(1.0, Timer_Phase2);
        } else {
            g_bVoteActive = false;
        }
    } else if (action == MenuAction_End) {
        if (StrEqual(g_sWinningGroup, "") && !g_bPhase1TieBreakActive) {
            g_bVoteActive = false;
        }
        delete menu;
    }
    return 0;
}

// --- FASE 2: MAPA ---
public Action Timer_Phase2(Handle timer) {
    if (timer == g_hPhase2Timer) {
        g_hPhase2Timer = null;
    }

    if (!g_bVoteActive || StrEqual(g_sWinningGroup, "")) {
        return Plugin_Stop;
    }

    Menu menu = new Menu(H_Phase2);
    menu.VoteResultCallback = VCB_Phase2;
    char title[128];
    Format(title, sizeof(title), "%T", "Menu_Title_Phase2", LANG_SERVER, g_sWinningGroup);
    menu.SetTitle(title);

    g_alCurrentVoteOptions.Clear();
    ArrayList alP;
    g_smGroupMaps.GetValue(g_sWinningGroup, alP);

    if (alP != null) {
        ArrayList alT = alP.Clone();
        int add = 0;

        StringMapSnapshot snap = g_smPlayerNoms.Snapshot();
        for (int i = 0; i < snap.Length; i++) {
            char steam[32], nomMap[64];
            snap.GetKey(i, steam, sizeof(steam));
            g_smPlayerNoms.GetString(steam, nomMap, sizeof(nomMap));

            char mapGroup[64];
            if (g_smMapToGroup.GetString(nomMap, mapGroup, sizeof(mapGroup)) && StrEqual(mapGroup, g_sWinningGroup)) {
                if (!IsMapEntryInHistory(nomMap)) {
                    if (g_alCurrentVoteOptions.FindString(nomMap) == -1) {
                        char nomDisplay[64];
                        GetMapEntryDisplayName(nomMap, nomDisplay, sizeof(nomDisplay));
                        menu.AddItem(nomMap, nomDisplay);
                        g_alCurrentVoteOptions.PushString(nomMap);
                        add++;
                    }

                    int idx = alT.FindString(nomMap);
                    if (idx != -1) {
                        alT.Erase(idx);
                    }

                    if (add >= g_cvMaxMaps.IntValue) {
                        break;
                    }
                }
            }
        }
        delete snap;

        while (add < g_cvMaxMaps.IntValue && alT.Length > 0) {
            int r = GetRandomInt(0, alT.Length - 1);
            char m[64];
            alT.GetString(r, m, sizeof(m));
            if (!IsMapEntryInHistory(m)) {
                if (g_alCurrentVoteOptions.FindString(m) == -1) {
                    char mapDisplay[64];
                    GetMapEntryDisplayName(m, mapDisplay, sizeof(mapDisplay));
                    menu.AddItem(m, mapDisplay);
                    g_alCurrentVoteOptions.PushString(m);
                    add++;
                }
            }
            alT.Erase(r);
        }

        if (add == 0) {
            for (int i = 0; i < alP.Length && add < g_cvMaxMaps.IntValue; i++) {
                char fallbackMap[64];
                alP.GetString(i, fallbackMap, sizeof(fallbackMap));
                if (g_alCurrentVoteOptions.FindString(fallbackMap) == -1) {
                    char fallbackDisplay[64];
                    GetMapEntryDisplayName(fallbackMap, fallbackDisplay, sizeof(fallbackDisplay));
                    menu.AddItem(fallbackMap, fallbackDisplay);
                    g_alCurrentVoteOptions.PushString(fallbackMap);
                    add++;
                }
            }
        }
        delete alT;
    }

    if (g_alCurrentVoteOptions.Length == 0) {
        LogError("UMI: Phase 2 aborted because group '%s' has no valid map options.", g_sWinningGroup);
        ResetVoteFlowState();
        delete menu;
        return Plugin_Stop;
    }

    PlayVoteSound(1);
    menu.ExitButton = false;
    if (!menu.DisplayVoteToAll(20)) {
        LogError("UMI: Failed to display phase 2 vote for group '%s'.", g_sWinningGroup);
        ResetVoteFlowState();
        delete menu;
        return Plugin_Stop;
    }
    return Plugin_Handled;
}

public int H_Phase2(Menu menu, MenuAction action, int p1, int p2) {
    if (action == MenuAction_VoteEnd) {
        char win[64];
        menu.GetItem(p1, win, sizeof(win));
        ResolvePhase2Winner(win);
    } else if (action == MenuAction_VoteCancel && p1 == VoteCancel_NoVotes) {
        char win[64];
        if (g_bPhase2TieBreakActive && menu.ItemCount > 0) {
            int randomItem = GetRandomInt(0, menu.ItemCount - 1);
            menu.GetItem(randomItem, win, sizeof(win));
        } else if (g_alCurrentVoteOptions.Length > 0) {
            g_alCurrentVoteOptions.GetString(GetRandomInt(0, g_alCurrentVoteOptions.Length - 1), win, sizeof(win));
        } else {
            GetCurrentMap(win, sizeof(win));
        }

        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                CPrintToChat(i, "%s%T", CHAT_PREFIX, "No_Votes_Map", i);
            }
        }
        ResolvePhase2Winner(win);
    } else if (action == MenuAction_End) {
        if (!g_bChangeOnRoundEnd && StrEqual(g_sNextMap, "") && !g_bPhase2TieBreakActive) {
            g_bVoteActive = false;
        }
        if (!g_bPhase2TieBreakActive) {
            strcopy(g_sWinningGroup, sizeof(g_sWinningGroup), "");
        }
        delete menu;
    }
    return 0;
}

void ProcessPhase2Win(const char[] win) {
    CapturePreviousNextMap();
    SetNextMapSelection(win);

    if (g_bNextMapIsWorkshop) {
        DebugLog("Phase2 winner is workshop entry '%s' (id=%s, fallback='%s').", g_sNextMap, g_sNextWorkshopId, g_sNextMapTarget);
    } else if (!SetNextMap(g_sNextMapTarget)) {
        LogError("UMI: SetNextMap failed for voted map '%s'.", g_sNextMapTarget);
    }
    PlayVoteSound(2);

    CancelPhase2Transition();
    CancelScheduledMapJump();
    g_bVoteActive = false;
    ResetRTVState();

    int act = (g_iTriggerType == 1) ? g_cvActionRTV.IntValue : g_cvActionAuto.IntValue;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            CPrintToChat(i, "%s%T", CHAT_PREFIX, (act == 0 ? "Vote_Won_Instant" : "Vote_Won_RoundEnd"), i, g_sNextMap);
        }
    }

    if (act == 0) {
        ScheduleMapJump(3.0);
    } else {
        g_bChangeOnRoundEnd = true;
    }
}

bool IsInHistory(const char[] map) {
    for (int i = 0; i < g_alMapHistory.Length; i++) {
        char m[64];
        g_alMapHistory.GetString(i, m, sizeof(m));
        if (StrEqual(map, m, false)) {
            return true;
        }
    }
    return false;
}

// --- COMANDOS ---
public Action Cmd_RTV(int client, int args) {
    if (!IsValidHumanClient(client) || g_bVoteActive || g_bPlayerRTVd[client]) {
        return Plugin_Handled;
    }

    float timeleft = GetGameTime() - g_fMapStartTime;
    if (timeleft < g_cvRTVDelay.FloatValue * 60.0) {
        int diff = RoundToNearest((g_cvRTVDelay.FloatValue * 60.0) - timeleft);
        CPrintToChat(client, "%s%T", CHAT_PREFIX, "RTV_Denied", client, diff / 60, diff % 60);
        return Plugin_Handled;
    }

    g_bPlayerRTVd[client] = true;
    g_iVotesRTV++;
    int req = RoundToCeil(GetRealCount() * g_cvRTVRatio.FloatValue);

    if (!StrEqual(g_sNextMap, "")) {
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                CPrintToChat(i, "%s%T", CHAT_PREFIX, "RTV_Skip_Initiated", i, client, g_iVotesRTV, req);
            }
        }

        if (g_iVotesRTV >= req) {
            for (int i = 1; i <= MaxClients; i++) {
                if (IsClientInGame(i) && !IsFakeClient(i)) {
                    CPrintToChat(i, "%s%T", CHAT_PREFIX, "RTV_Skip_Won", i, g_sNextMap);
                }
            }
            ResetRTVState();
            ScheduleMapJump(3.0);
        }
    } else {
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                CPrintToChat(i, "%s%T", CHAT_PREFIX, "RTV_Initiated", i, client, g_iVotesRTV, req);
            }
        }
        if (g_iVotesRTV >= req) {
            if (!StartPhase1(1)) {
                LogError("UMI: RTV threshold reached but phase 1 could not start.");
                ResetRTVState();
            }
        }
    }
    return Plugin_Handled;
}

public Action Cmd_Nominate(int client, int args) {
    if (!IsValidHumanClient(client)) {
        return Plugin_Handled;
    }

    if (!StrEqual(g_sNextMap, "")) {
        CPrintToChat(client, "%s%T", CHAT_PREFIX, "Nominate_Denied_Decided", client, g_sNextMap);
        return Plugin_Handled;
    }

    Menu m = new Menu(H_NomGroup);
    char title[128];
    Format(title, sizeof(title), "%T", "Menu_Title_Nominate_Mod", client);
    m.SetTitle(title);
    for (int i = 0; i < g_alGroupNames.Length; i++) {
        char n[64];
        g_alGroupNames.GetString(i, n, sizeof(n));
        m.AddItem(n, n);
    }
    m.Display(client, 20);
    return Plugin_Handled;
}

public int H_NomGroup(Menu m, MenuAction a, int p1, int p2) {
    if (a == MenuAction_Select) {
        char g[64];
        m.GetItem(p2, g, sizeof(g));

        Menu m2 = new Menu(H_NomMap);
        char title[128];
        Format(title, sizeof(title), "%T", "Menu_Title_Nominate_Map", p1, g);
        m2.SetTitle(title);

        ArrayList al;
        g_smGroupMaps.GetValue(g, al);
        if (al == null || al.Length == 0) {
            CPrintToChat(p1, "%s%T", CHAT_PREFIX, "Group_Unavailable_Reloaded", p1, g);
            DebugLog("Nomination group '%s' unavailable for client %d (menu stale after reload).", g, p1);
            delete m2;
            return 0;
        }

        for (int i = 0; i < al.Length; i++) {
            char map[64];
            char mapDisplay[64];
            al.GetString(i, map, sizeof(map));
            GetMapEntryDisplayName(map, mapDisplay, sizeof(mapDisplay));

            if (IsMapEntryInHistory(map)) {
                char disp[128];
                Format(disp, sizeof(disp), "%s (%T)", mapDisplay, "Recently_Played", p1);
                m2.AddItem(map, disp, ITEMDRAW_DISABLED);
            } else {
                bool alNom = false;
                StringMapSnapshot snap = g_smPlayerNoms.Snapshot();
                for (int j = 0; j < snap.Length; j++) {
                    char k[32], v[64];
                    snap.GetKey(j, k, sizeof(k));
                    g_smPlayerNoms.GetString(k, v, sizeof(v));
                    if (StrEqual(map, v, false)) {
                        alNom = true;
                        break;
                    }
                }
                delete snap;

                if (alNom) {
                    char d[128];
                    Format(d, sizeof(d), "%s (%T)", mapDisplay, "Already_Nominated", p1);
                    m2.AddItem(map, d, ITEMDRAW_DISABLED);
                } else {
                    m2.AddItem(map, mapDisplay);
                }
            }
        }
        m2.Display(p1, 20);
    } else if (a == MenuAction_End) {
        delete m;
    }
    return 0;
}

public int H_NomMap(Menu m, MenuAction a, int p1, int p2) {
    if (a == MenuAction_Select) {
        char map[64], steam[32];
        char mapDisplay[64], workshopId[32], workshopMap[64];
        m.GetItem(p2, map, sizeof(map));
        GetMapEntryDisplayName(map, mapDisplay, sizeof(mapDisplay));
        bool isWorkshop = GetWorkshopInfoForEntry(map, workshopId, sizeof(workshopId), workshopMap, sizeof(workshopMap));

        if (!isWorkshop) {
            bool valid = IsMapValid(map);
            if (g_cvStrictMapValidation.BoolValue && !valid) {
                CPrintToChat(p1, "%s%T", CHAT_PREFIX, "Nominate_Invalid_Map", p1, mapDisplay);
                LogError("UMI: Nomination blocked for invalid map '%s'.", map);
                return 0;
            }
            if (!valid) {
                DebugLog("Nomination map '%s' accepted in soft validation mode.", map);
            }
        } else {
            DebugLog("Nomination workshop entry '%s' (%s).", mapDisplay, workshopId);
        }
        if (!GetClientAuthId(p1, AuthId_Steam2, steam, sizeof(steam), true)) {
            CPrintToChat(p1, "%s%T", CHAT_PREFIX, "Nominate_SteamID_NotReady", p1);
            return 0;
        }
        g_smPlayerNoms.SetString(steam, map);

        char grp[64];
        g_smMapToGroup.GetString(map, grp, sizeof(grp));
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                CPrintToChat(i, "%s%T", CHAT_PREFIX, "Map_Nominated", i, p1, mapDisplay, grp);
            }
        }
    } else if (a == MenuAction_End) {
        delete m;
    }
    return 0;
}

public Action Listener_Chat(int client, const char[] cmd, int argc) {
    if (client <= 0 || client > MaxClients) {
        return Plugin_Continue;
    }

    char t[32];
    GetCmdArgString(t, sizeof(t));
    StripQuotes(t);
    TrimString(t);

    if (StrEqual(t, "rtv", false)) {
        Cmd_RTV(client, 0);
    } else if (StrEqual(t, "nominate", false)) {
        Cmd_Nominate(client, 0);
    }
    return Plugin_Continue;
}

public Action Timer_CheckTime(Handle t) {
    int tl;
    if (GetMapTimeLeft(tl)) {
        float voteWindow = g_cvVoteTime.FloatValue * 60.0;
        if (tl > 0 && float(tl) <= voteWindow && !g_bVoteActive && !g_bAutoVoteFired) {
            if (StrEqual(g_sNextMap, "")) {
                if (StartPhase1(2)) {
                    g_bAutoVoteFired = true;
                } else {
                    DebugLog("Auto-vote trigger skipped because phase 1 could not start.");
                }
            }
        } else if (tl <= 0 && !StrEqual(g_sNextMap, "")) {
            ScheduleMapJump(1.0);
        }
    }
    return Plugin_Continue;
}

public Action Timer_Jump(Handle t) {
    if (t == g_hMapJumpTimer) {
        g_hMapJumpTimer = null;
    }
    g_bMapChangeScheduled = false;

    if (StrEqual(g_sNextMap, "")) {
        return Plugin_Stop;
    }

    if (IsVoteInProgress()) {
        CancelVote();
    }

    if (g_bNextMapIsWorkshop) {
        if (!TryChangeToWorkshopMap(g_sNextWorkshopId, g_sNextMapTarget)) {
            LogError("UMI: Workshop map change failed for '%s' (id=%s).", g_sNextMap, g_sNextWorkshopId);
            ClearNextMapSelection();
        }
        return Plugin_Handled;
    }

    if (g_sNextMapTarget[0] == '\0') {
        LogError("UMI: No map target set for next map '%s'.", g_sNextMap);
        ClearNextMapSelection();
        return Plugin_Stop;
    }

    ForceChangeLevel(g_sNextMapTarget, "UMI Change");
    return Plugin_Handled;
}

public Action Event_RoundEnd(Event e, const char[] n, bool d) {
    if (g_bChangeOnRoundEnd) {
        ScheduleMapJump(2.0);
    }
    return Plugin_Continue;
}

int GetRealCount() {
    int c = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            c++;
        }
    }
    return (c == 0) ? 1 : c;
}

// ==========================================
// MENU DE ADMIN: SETEAR SIGUIENTE MAPA
// ==========================================
void ShowAdminSetNextGroupMenu(int client) {
    Menu m = new Menu(H_AdminSetNextGroup);
    char title[128];
    Format(title, sizeof(title), "%T", "Admin_Menu_SetNext", client);
    m.SetTitle(title);
    for (int i = 0; i < g_alGroupNames.Length; i++) {
        char n[64];
        g_alGroupNames.GetString(i, n, sizeof(n));
        m.AddItem(n, n);
    }
    m.Display(client, MENU_TIME_FOREVER);
}

public int H_AdminSetNextGroup(Menu m, MenuAction a, int p1, int p2) {
    if (a == MenuAction_Select) {
        char g[64];
        m.GetItem(p2, g, sizeof(g));
        ShowAdminSetNextMapMenu(p1, g);
    } else if (a == MenuAction_End) {
        delete m;
    }
    return 0;
}

void ShowAdminSetNextMapMenu(int client, const char[] group) {
    Menu m = new Menu(H_AdminSetNextMap);
    char title[128];
    Format(title, sizeof(title), "%T", "Admin_Menu_SetNext", client);
    m.SetTitle(title);

    ArrayList al;
    g_smGroupMaps.GetValue(group, al);
    if (al == null || al.Length == 0) {
        CPrintToChat(client, "%s%T", CHAT_PREFIX, "Group_Unavailable_Reloaded", client, group);
        DebugLog("Admin group '%s' unavailable for client %d (menu stale after reload).", group, client);
        delete m;
        return;
    }

    for (int i = 0; i < al.Length; i++) {
        char map[64];
        char mapDisplay[64];
        al.GetString(i, map, sizeof(map));
        GetMapEntryDisplayName(map, mapDisplay, sizeof(mapDisplay));
        m.AddItem(map, mapDisplay);
    }
    m.ExitButton = true;
    m.Display(client, MENU_TIME_FOREVER);
}

public int H_AdminSetNextMap(Menu m, MenuAction a, int p1, int p2) {
    if (a == MenuAction_Select) {
        char map[64];
        m.GetItem(p2, map, sizeof(map));
        strcopy(g_sAdminSelectedMap[p1], sizeof(g_sAdminSelectedMap[]), map);
        ShowAdminSetNextTimingMenu(p1);
    } else if (a == MenuAction_End) {
        delete m;
    }
    return 0;
}

void ShowAdminSetNextTimingMenu(int client) {
    Menu m = new Menu(H_AdminSetNextTiming);
    char title[128];
    char selectedDisplay[64];
    GetMapEntryDisplayName(g_sAdminSelectedMap[client], selectedDisplay, sizeof(selectedDisplay));
    Format(title, sizeof(title), "%T\n ", "Admin_Menu_SetNext_Timing", client, selectedDisplay);
    m.SetTitle(title);

    char opt1[64], opt2[64], opt3[64];
    Format(opt1, sizeof(opt1), "%T", "Admin_Menu_Timing_Now", client);
    Format(opt2, sizeof(opt2), "%T", "Admin_Menu_Timing_Round", client);
    Format(opt3, sizeof(opt3), "%T", "Admin_Menu_Timing_MapEnd", client);

    m.AddItem("now", opt1);
    m.AddItem("round", opt2);
    m.AddItem("mapend", opt3);
    m.ExitButton = true;
    m.Display(client, MENU_TIME_FOREVER);
}

public int H_AdminSetNextTiming(Menu m, MenuAction a, int p1, int p2) {
    if (a == MenuAction_Select) {
        char info[32];
        m.GetItem(p2, info, sizeof(info));

        char mapEntry[64];
        strcopy(mapEntry, sizeof(mapEntry), g_sAdminSelectedMap[p1]);

        if (g_bVoteActive) {
            if (IsVoteInProgress()) {
                CancelVote();
            }
            ResetVoteFlowState();
        }

        CancelScheduledMapJump();
        CapturePreviousNextMap();
        SetNextMapSelection(mapEntry);
        if (g_bNextMapIsWorkshop) {
            DebugLog("Admin selected workshop next map '%s' (id=%s, fallback='%s').", g_sNextMap, g_sNextWorkshopId, g_sNextMapTarget);
        }
        if (!g_bNextMapIsWorkshop && !SetNextMap(g_sNextMapTarget)) {
            LogError("UMI: SetNextMap failed for admin-selected map '%s'.", g_sNextMapTarget);
        }
        ResetRTVState();

        if (StrEqual(info, "now")) {
            g_bChangeOnRoundEnd = false;
            ScheduleMapJump(3.0);
        } else if (StrEqual(info, "round")) {
            g_bChangeOnRoundEnd = true;
        } else if (StrEqual(info, "mapend")) {
            g_bChangeOnRoundEnd = false;
        }

        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                char tStr[64];
                if (StrEqual(info, "now")) {
                    Format(tStr, sizeof(tStr), "%T", "Admin_Menu_Timing_Now", i);
                } else if (StrEqual(info, "round")) {
                    Format(tStr, sizeof(tStr), "%T", "Admin_Menu_Timing_Round", i);
                } else {
                    Format(tStr, sizeof(tStr), "%T", "Admin_Menu_Timing_MapEnd", i);
                }

                CPrintToChat(i, "%s%T", CHAT_PREFIX, "Admin_Action_SetNext", i, g_sNextMap, tStr);
            }
        }
    } else if (a == MenuAction_End) {
        delete m;
    }
    return 0;
}
