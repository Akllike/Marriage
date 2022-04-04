#include <scp>
#include <sourcemod>

#pragma semicolon 1
#pragma tabsize 0 

#define DATABASE_NAME "marriage"
#define NOT_PREFIX "NOT_PREFIX"
#define CREATE_TABE_PAIR "CREATE TABLE IF NOT EXISTS `pair` (`id` INTEGER PRIMARY KEY AUTOINCREMENT, `first` INTEGER NOT NULL, `second` INTEGER NOT NULL, `tag` VARCHAR (64) NOT NULL%s, `time` INTEGER NOT NULL);"
#define CREATE_TABE_KILLS "CREATE TABLE IF NOT EXISTS `kills` (`accountid` INTEGER NOT NULL PRIMARY KEY, `name` VARCHAR NOT NULL%s, `kills` INTEGER NOT NULL);"
#define SELECT_PLAYER "SELECT `first`, `second`, `tag`, `k`.`kills`, `k1`.`kills`, `k`.`name`, `k1`.`name`, `time` FROM ((`pair` AS `p`) LEFT JOIN `kills` AS `k` ON (`p`.`first` = `k`.`accountid`)) LEFT JOIN `kills` AS `k1` ON (`p`.`second` = `k1`.`accountid`) WHERE `first` = %i OR `second` = %i"
#define SELECT_ALL_PLAYERS "SELECT `first`, `second`, `k`.`kills`, `k1`.`kills`, `k`.`name`, `k1`.`name`, `time` FROM ((`pair` AS `p`) LEFT JOIN `kills` AS `k` ON (`p`.`first` = `k`.`accountid`)) LEFT JOIN `kills` AS `k1` ON (`p`.`second` = `k1`.`accountid`)"

#define SELECT_TOP_KILLS "SELECT `k`.`name` AS `first`, `k1`.`name` AS `second`, (`k`.kills + `k1`.`kills`) AS `kils` FROM (((`pair` AS `p`) LEFT JOIN `kills` AS `k` ON (`p`.`first` = `k`.`accountid`)) LEFT JOIN `kills` AS `k1` ON (`p`.`second` = `k1`.`accountid`)) ORDER BY (`k`.`kills` + `k1`.`kills`) DESC LIMIT 10"
#define SELECT_TOP_TIME "SELECT `k`.`name` AS `first`, `k1`.`name` AS `second`, `p`.`time` FROM (((`pair` AS `p`) LEFT JOIN `kills` AS `k` ON (`p`.`first` = `k`.`accountid`)) LEFT JOIN `kills` AS `k1` ON (`p`.`second` = `k1`.`accountid`)) ORDER BY `p`.`time`"

#define INSERT_INTO_PAIR "INSERT INTO `pair` (`first`, `second`, `tag`, `time`) VALUES (%i, %i, '%s', %i)"
#define INSERT_INTO_KILLS "INSERT INTO `kills` (`accountid`, `name`, `kills`) VALUES (%i, '%N', 0)"

#define UPDATE_KILLS "UPDATE `kills` SET `kills` = %i, `name` = '%N' WHERE `accountid` = %i"

#define DELETE_PAIR "DELETE FROM `pair` WHERE `first` = %i"
#define DELETE_KILLS "DELETE FROM `kills` WHERE `accountid` = %i"

Database g_hDatabase;

enum struct PlayerInfo
{
	bool bSay;
	bool bMarried;

	int iAccountID;
	int iKills;
	int iPairKills;
	int iSignificantOther;
	int iTime;

	char szTag[64];
	char szNick[64];

	void Init(DBResultSet hResult, int iAccountID)
	{
		this.iAccountID = iAccountID;

		if(hResult.FetchRow())
		{
			this.bMarried = true;
			hResult.FetchString(2, this.szTag, 64);
			this.iTime = hResult.FetchInt(7);

			if(hResult.FetchInt(0) == iAccountID)
			{
				this.iSignificantOther = hResult.FetchInt(1);
				this.iKills = hResult.FetchInt(3);
				hResult.FetchString(6, this.szNick, 64);
				this.iPairKills = hResult.FetchInt(4);
			}
			else
			{
				this.iSignificantOther = hResult.FetchInt(0);
				this.iKills = hResult.FetchInt(4);
				hResult.FetchString(5, this.szNick, 64);
				this.iPairKills = hResult.FetchInt(3);
			}
		}
		else
		{
			this.bMarried = false;
			this.iSignificantOther = -1;
			this.szTag[0] = '\0';
			this.iKills = 0;
		}

		this.bSay = false;
	}

	void Save(int iClient)
	{
		if(this.bMarried)
		{
			static char szQuery[512];

			g_hDatabase.Format(szQuery, sizeof szQuery, UPDATE_KILLS, this.iKills, iClient,this.iAccountID);
			g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery);
		}
	}
}

PlayerInfo Player[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name		= "Marriage [03.04.2022]",
	author		= "phenom",
	version		= "1.5.2",
	url			= "https://hlmod.ru/"
};

public void OnPluginStart()
{
	HookEvent("player_death", Event_Death);
	//HookEvent("player_say", Say);

	RegConsoleCmd("sm_brak", CallBack_Command);
	RegConsoleCmd("family", MPinfo);

	LoadDatabase();
}

public void OnClientDisconnect(int iClient)
{
	if(!IsFakeClient(iClient))
	{
		Player[iClient].Save(iClient);
	}
}

void Event_Death(Event event, const char[] name, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(event.GetInt("attacker"));

	if(iClient > 0 && iClient != GetClientOfUserId(event.GetInt("userid")) && Player[iClient].bMarried)
	{
		Player[iClient].iKills++;
	}
}

Action MPinfo(int iClient, int iArgs)
{
	if(!Player[iClient].bMarried)
	{
		PrintToChat(iClient, "\x01[\x04Система\x01] \x04Вы не можете поставить тег, так как не состоите в браке!");
		return;
	}

	char szQuery[512], szTag[32];
	GetCmdArg(1, szTag, sizeof(szTag));

	if(!iArgs)
	{
		PrintToChat(iClient, "\x01[\x04Система\x01] \x04Введите тег семьи в виде команды: \x03!family Ивановы");
		return;
	}

	FormatEx(szQuery, sizeof szQuery, "UPDATE `pair` SET `tag` = '%s' WHERE `pair`.`second` = %i OR `pair`.`first` = %i", szTag, Player[iClient].iAccountID, Player[iClient].iAccountID);
	g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery);
	PrintToChat(iClient, "\x01[\x04Система\x01] \x04Вы успешно сменили тег на - \x03%s! \n\x04Изменения вступят в силу после смены карты.", szTag);
}

void LoadDatabase()
{
	if(SQL_CheckConfig(DATABASE_NAME))
	{
		Database.Connect(CallBack_Database, DATABASE_NAME);
	}
	else
	{
		char szError[256];
		KeyValues hKV = new KeyValues(NULL_STRING, "driver", "sqlite");
		hKV.SetString("database", DATABASE_NAME);

		Database hDatabase = SQL_ConnectCustom(hKV, szError, sizeof szError, false);

		CallBack_Database(hDatabase, szError, 0);

		hKV.Close();
	}
}

void CallBack_Database(Database hDB, const char[] szError, any data)
{
	if(hDB == null || szError[0])
	{
		SetFailState("[Marriage] Database failure: %s", szError);

		return;
	}

	delete g_hDatabase;
	g_hDatabase = hDB;

	CreateTables();

	for(int i = MaxClients + 1; --i;)
	{
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
		{
			LoadClient(i, GetSteamAccountID(i));
		}
	}
}

void CreateTables()
{
	char szDriver[8];
	Transaction tTransaction = new Transaction();

	g_hDatabase.Driver.GetIdentifier(szDriver, sizeof szDriver);

	if(szDriver[0] == 's')
	{
		CreateTableTransactions(tTransaction);
	}
	else
	{
		CreateTableTransactions(tTransaction, " COLLATE 'utf8mb4_general_ci'");

		tTransaction.AddQuery("SET NAMES 'utf8';");
		tTransaction.AddQuery("SET CHARSET 'utf8';");
	}

	g_hDatabase.Execute(tTransaction, TransSuccess, TransFailure, 0, DBPrio_High);
}

void CreateTableTransactions(Transaction &tTransaction, char[] szUTF8MB4 = NULL_STRING)
{
	char szQuery[512];
	FormatEx(szQuery, sizeof szQuery, CREATE_TABE_PAIR, szUTF8MB4);
	tTransaction.AddQuery(szQuery);

	FormatEx(szQuery, sizeof szQuery, CREATE_TABE_KILLS, szUTF8MB4);
	tTransaction.AddQuery(szQuery);
}

void TransSuccess(Database db, int iData, int numQueries, DBResultSet[] hResults, any[] queryData)
{

}

void TransFailure(Database db, any data, int numQueries, const char[] szError, int failIndex, any[] queryData)
{
	if(szError[0])
	{
		LogError("TransFailure [%s] %i", szError, failIndex);
	}
}

public void OnClientAuthorized(int iClient, const char[] szAuth)
{
	if(!IsFakeClient(iClient))
	{
		int iAccountID = GetSteamAccountID(iClient);

		for(int i = MaxClients + 1; --i;)
		{
			if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && i != iClient && Player[i].bMarried && Player[i].iSignificantOther == iAccountID)
			{
				PrintToChat(i, "\x01[\x04Система\x01] \x04Ваша вторая половинка \x03%N \x04заходит на сервер", iClient);

				break;
			}
		}

		LoadClient(iClient, iAccountID);
	}
}

void LoadClient(int iClient, int iAccountID)
{
	if(iAccountID != 0)
	{
		static char szQuery[512];

		DataPack hPack = new DataPack();
		hPack.WriteCell(GetClientUserId(iClient));
		hPack.WriteCell(iAccountID);

		FormatEx(szQuery, sizeof szQuery, SELECT_PLAYER, iAccountID, iAccountID);
		g_hDatabase.Query(CallBack_LoadClient, szQuery, hPack);
	}
}

void CallBack_LoadClient(Database hDB, DBResultSet hResults, const char[] szError, DataPack hPack)
{
	if(szError[0])
	{
		LogError("CallBack_LoadClient: %s", szError);
	}

	hPack.Reset();
	int iClient = GetClientOfUserId(hPack.ReadCell());

	if(iClient > 0 && IsClientConnected(iClient))
	{
		Player[iClient].Init(hResults, hPack.ReadCell());
	}

	delete hPack;
}

public Action OnChatMessage(int &iClient, Handle hRecipients, char[] szName, char[] szMessage)
{
	if(iClient > 0 && IsClientInGame(iClient) && Player[iClient].bMarried && Player[iClient].szTag[0])
	{
		Format(szName, MAXLENGTH_NAME, "\x03[\x04%s\x03] \x01%s", Player[iClient].szTag, szName);
	}
}

Action CallBack_Command(int iClient, int iArgs)
{
	if(iClient > 0)
	{
		Open_MainMenu(iClient);
	}

	return Plugin_Handled;
}

void Open_MainMenu(int iClient)
{
	Handle hMenu = CreateMenu(CallBack_MainMenu);

	static char szBuffer[256];

	if(Player[iClient].bMarried)
	{
		static char szTime[128];

		GetStringTime(GetTime() - Player[iClient].iTime, szTime, sizeof szTime);
		FormatEx(szBuffer, sizeof szBuffer, "Marriage | Меню \n \nВаша пара: %s \nВаши киллы: %i / %i [%i] \nТег в чате: %s \nВремя в браке: %s\n ", Player[iClient].szNick, Player[iClient].iKills, Player[iClient].iPairKills, Player[iClient].iKills + Player[iClient].iPairKills, Player[iClient].szTag[0] ? Player[iClient].szTag :" [отсутствует]", szTime);
	}
	else
	{
		FormatEx(szBuffer, sizeof szBuffer, "Marriage | Меню\n ");
	}

	SetMenuTitle(hMenu, szBuffer);

	AddMenuItem(hMenu, "", "Создать брак с игроком");
	AddMenuItem(hMenu, "", "Разорвать брак\n ");
	AddMenuItem(hMenu, "", "ТОП по киллам");

	if(GetUserFlagBits(iClient) & ADMFLAG_ROOT)
	{
		AddMenuItem(hMenu, "", "ТОП по времени в браке\n ");
		AddMenuItem(hMenu, "", "Развести пару");
	}
	else
	{
		AddMenuItem(hMenu, "", "ТОП по времени в браке");
	}

	DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
}

int CallBack_MainMenu(Menu hMenu, MenuAction eAction, int iClient, int iItem)
{
	switch(eAction)
	{
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
		case MenuAction_Select:
		{
			switch(iItem)
			{
				case 0:
				{
					if(Player[iClient].bMarried)
					{
						PrintToChat(iClient, "\x01[\x04Система\x01] \x03Вы уже в браке, \x04Вы не можете создать новый брак, пока не разведетесь!");
						Open_MainMenu(iClient);

						return 0;
					}

					Open_PlayerListMenu(iClient);
				}
				case 1:
				{
					if(Player[iClient].bMarried)
					{
						Handle hMenu2 = CreateMenu(CallBack_DivorceMenu);

						SetMenuTitle(hMenu2, "Вы уверены, что хотите развестись?");

						AddMenuItem(hMenu2, "", "Да");
						AddMenuItem(hMenu2, "", "Нет");

						SetMenuExitBackButton(hMenu2, true);
						DisplayMenu(hMenu2, iClient, MENU_TIME_FOREVER);
					}
					else
					{
						PrintToChat(iClient, "\x01[\x04Система\x01] \x03Вы не в браке, \x04Вы не можете развестись");
						Open_MainMenu(iClient);
					}
				}
				case 2:
				{
					Open_TopKillsPanel(iClient);
				}
				case 3:
				{
					Open_TopTimePanel(iClient);
				}
				case 4:
				{
					Open_AdminMenu(iClient);
				}
			}
		}
	}

	return 0;
}

int CallBack_DivorceMenu(Menu hMenu, MenuAction eAction, int iClient, int iItem)
{
	switch(eAction)
	{
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				Open_MainMenu(iClient);
			}
		}
		case MenuAction_Select:
		{
			if(iItem == 0)
			{
				static char szQuery[512];

				FormatEx(szQuery, sizeof szQuery, SELECT_PLAYER, Player[iClient].iAccountID, Player[iClient].iAccountID);
				g_hDatabase.Query(CallBack_Divorce, szQuery, GetClientUserId(iClient));
			}

			Open_MainMenu(iClient);
		}
	}

	return 0;
}

void CallBack_Divorce(Database hDB, DBResultSet hResults, const char[] szError, int iClient)
{
	if(szError[0])
	{
		LogError("CallBack_Divorce: %s", szError);
	}

	if(hResults.FetchRow())
	{
		static char szQuery[512];

		iClient = GetClientOfUserId(iClient);

		if(iClient > 0 && IsClientConnected(iClient))
		{
			PrintToChat(iClient, "\x01[\x04Система\x01] \x04Вы развелись с \x03%s", Player[iClient].szNick);

			for(int i = MaxClients + 1; --i;)
			{
				if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && i != iClient && GetSteamAccountID(i) == Player[iClient].iSignificantOther)
				{
					PrintToChat(i, "\x01[\x04Система\x01] \x04С вами развелся(лась) \x03%N", iClient);

					break;
				}
			}
		}

		FormatEx(szQuery, sizeof szQuery, DELETE_PAIR, hResults.FetchInt(0));
		g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery);

		FormatEx(szQuery, sizeof szQuery, DELETE_KILLS, hResults.FetchInt(0));
		g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery);

		FormatEx(szQuery, sizeof szQuery, DELETE_KILLS, hResults.FetchInt(1));
		g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery, 10);
	}
}

void Open_PlayerListMenu(int iClient)
{
	static char szBuffer[128], szId[8];
	Handle hMenu = CreateMenu(CallBack_PlayerListMenu);

	SetMenuTitle(hMenu, "Marriage | Выберете себе пару:\n ");

	for(int i = MaxClients + 1; --i;)
	{
		if(IsClientConnected(i) && !IsFakeClient(i) && i != iClient && Player[i].bMarried == false)
		{
			IntToString(GetClientUserId(i), szId, sizeof szId);
			GetClientName(i, szBuffer, sizeof szBuffer);
			AddMenuItem(hMenu, szId, szBuffer);
		}
	}

	if(GetMenuItemCount(hMenu) == 0)
	{
		AddMenuItem(hMenu, "", "Остутствуют игроки", ITEMDRAW_DISABLED);
	}

	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
}

int CallBack_PlayerListMenu(Menu hMenu, MenuAction eAction, int iClient, int iItem)
{
	switch(eAction)
	{
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				Open_MainMenu(iClient);
			}
		}
		case MenuAction_Select:
		{
			static char szId[8];
			hMenu.GetItem(iItem, szId, sizeof szId);

			int iTarget = GetClientOfUserId(StringToInt(szId));

			if(IsClientInGame(iTarget))
			{
				if(Player[iTarget].bMarried == false)
				{
					Player[iClient].iSignificantOther = StringToInt(szId);
					Player[iClient].bSay = true;
					PrintToChat(iClient, "\x01[\x04Система\x01] \x04Введите в чат префикс(тег) или напишите \x03cancel \x04для того чтобы префикса(тега) не было");
				}
				else
				{
					PrintToChat(iClient, "\x01[\x04Система\x01] \x04Игрок \x03%N \x04уже состоит в браке!", iTarget);
				}
			}
			else
			{
				Player[iClient].iSignificantOther = -1;
				PrintToChat(iClient, "\x01[\x04Система\x01] \x03Выбранная вами пара не в игре");
			}
		}
	}

	return 0;
}

public Action OnClientSayCommand(int iClient, const char[] command, const char[] sArgs)
{
	if(Player[iClient].bSay)
	{
		static char szBuffer[128];
		Player[iClient].bSay = false;

		if(strcmp(sArgs, "cancel") == 0)
		{
			Player[iClient].szTag[0] = '\0';
			FormatEx(szBuffer, sizeof szBuffer, "Игрок %N делает вам предложение руки и сердца \nБез тега в чате\n ", iClient);
		}
		else
		{
			strcopy(Player[iClient].szTag, 64, sArgs);
			FormatEx(szBuffer, sizeof szBuffer, "Игрок %N делает вам предложение руки и сердца \nС тегом в чате: %s\n ", iClient, sArgs);
		}

		Handle hMenu = CreateMenu(CallBack_SentenceMenu);

		SetMenuTitle(hMenu, szBuffer);

		AddMenuItem(hMenu, "", "Согласиться");
		AddMenuItem(hMenu, "", "Отказаться");

		DisplayMenu(hMenu, GetClientOfUserId(Player[iClient].iSignificantOther), MENU_TIME_FOREVER);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

int CallBack_SentenceMenu(Menu hMenu, MenuAction eAction, int iClient, int iItem)
{
	switch(eAction)
	{
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
		case MenuAction_Select:
		{
			int iTarget = -1;

			for(int i = MaxClients + 1; --i;)
			{
				if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && i != iClient && Player[i].bMarried == false && Player[i].iSignificantOther == GetClientUserId(iClient))
				{
					iTarget = i;

					break;
				}
			}

			switch(iItem)
			{
				case 0:
				{
					if(iTarget == -1)
					{
						PrintToChat(iClient, "\x01[\x04Система\x01] \x03Игрок, который делал вам предложение, вышел");
					}
					else
					{
						if(Player[iTarget].bMarried == false)
						{
							char szQuery[512];
							FormatEx(szQuery, sizeof szQuery, INSERT_INTO_PAIR, Player[iTarget].iAccountID, Player[iClient].iAccountID, Player[iTarget].szTag, GetTime());
							g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery);

							g_hDatabase.Format(szQuery, sizeof szQuery, INSERT_INTO_KILLS, Player[iTarget].iAccountID, iTarget);
							g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery);

							g_hDatabase.Format(szQuery, sizeof szQuery, INSERT_INTO_KILLS, Player[iClient].iAccountID, iClient);
							g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery, 10);

							PrintToChat(iTarget, "\x01[\x04Система\x01] \x03%N \x04принял ваше предложение", iClient);
							PrintToChat(iClient, "\x01[\x04Система\x01] \x04Вы приняли предложение от \x03%N", iTarget);
							PrintToChatAll("\x01[\x04Система\x01] \x03%N \x04и \x03%N \x04поженились, поздравим новую пару сервера!", iTarget, iClient);

						}
						else
						{
							PrintToChat(iClient, "\x01[\x04Система\x01] \x03Игрок, который делал вам предложение, уже состоит в браке");
						}
					}
				}
				case 1:
				{
					if(iTarget == -1)
					{
						PrintToChat(iClient, "\x01[\x04Система\x01] \x03Вы отказались от предложения");
					}
					else
					{
						PrintToChat(iClient, "\x01[\x04Система\x01] \x03Вы отказались от предложения \x04%N", iTarget);
						PrintToChat(iTarget, "\x01[\x04Система\x01] \x04%N \x03отказался(лась) от вашего предложения", iClient);
					}					
				}
			}
		}
	}

	return 0;
}

void Open_TopKillsPanel(int iClient)
{
	g_hDatabase.Query(CallBack_TopKills, SELECT_TOP_KILLS, GetClientUserId(iClient));
}

void CallBack_TopKills(Database hDB, DBResultSet hResults, const char[] szError, int iClient)
{
	if(szError[0])
	{
		LogError("CallBack_TopKills: %s", szError);
	}

	iClient = GetClientOfUserId(iClient);

	if(iClient > 0 && IsClientConnected(iClient))
	{
		static char szBuffer[256], szNameFirst[64], szNameSecond[64];
		Panel hPanel = new Panel();

		SetPanelTitle(hPanel, "Marriage | ТОП по киллам\n ");

		int iPos = 1;
		while(hResults.FetchRow())
		{
			hResults.FetchString(0, szNameFirst, sizeof szNameFirst);
			hResults.FetchString(1, szNameSecond, sizeof szNameSecond);

			FormatEx(szBuffer, sizeof szBuffer, "%i. %s + %s [%i]", iPos++, szNameFirst, szNameSecond, hResults.FetchInt(2));
			DrawPanelText(hPanel, szBuffer);
		}

		SetPanelCurrentKey(hPanel, 8);
		DrawPanelItem(hPanel, "Назад");

		SetPanelCurrentKey(hPanel, 10);
		DrawPanelItem(hPanel, "Выход");

		SendPanelToClient(hPanel, iClient, CallBack_Panel, MENU_TIME_FOREVER);

		delete hPanel;
	}
}

void Open_TopTimePanel(int iClient)
{
	g_hDatabase.Query(CallBack_TopTime, SELECT_TOP_TIME, GetClientUserId(iClient));
}

void CallBack_TopTime(Database hDB, DBResultSet hResults, const char[] szError, int iClient)
{
	if(szError[0])
	{
		LogError("CallBack_TopTime: %s", szError);
	}

	iClient = GetClientOfUserId(iClient);

	if(iClient > 0 && IsClientConnected(iClient))
	{
		static char szBuffer[256], szNameFirst[64], szNameSecond[64], szTime[128];
		Handle hMenu = CreateMenu(CallBack_TopTimeMenu);

		SetMenuTitle(hMenu, "Marriage | ТОП по времени в браке\n ");

		int iTime = GetTime();

		while(hResults.FetchRow())
		{
			hResults.FetchString(0, szNameFirst, sizeof szNameFirst);
			hResults.FetchString(1, szNameSecond, sizeof szNameSecond);

			GetStringTime(iTime - hResults.FetchInt(2), szTime, sizeof szTime);
			FormatEx(szBuffer, sizeof szBuffer, "%s + %s [%s]", szNameFirst, szNameSecond, szTime);
			AddMenuItem(hMenu, "", szBuffer, ITEMDRAW_DISABLED);
		}

		SetMenuExitBackButton(hMenu, true);
		DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
	}
}

int CallBack_TopTimeMenu(Menu hMenu, MenuAction eAction, int iClient, int iItem)
{
	switch(eAction)
	{
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				Open_MainMenu(iClient);
			}
		}
	}

	return 0;
}

void Open_AdminMenu(int iClient)
{
	g_hDatabase.Query(CallBack_Admin, SELECT_ALL_PLAYERS, GetClientUserId(iClient));
}

void CallBack_Admin(Database hDB, DBResultSet hResults, const char[] szError, int iClient)
{
	if(szError[0])
	{
		LogError("CallBack_Admin: %s", szError);
	}

	iClient = GetClientOfUserId(iClient);

	if(iClient > 0 && IsClientConnected(iClient))
	{
		char szBuffer[512], szInfo[512], szTime[256], szNameFirst[64], szNameSecond[64];

		Handle hMenu = CreateMenu(CallBack_AdminMenu);

		SetMenuTitle(hMenu, "Marriage | Развести пару\n ");

		while(hResults.FetchRow())
		{
			hResults.FetchString(4, szNameFirst, sizeof szNameFirst);
			hResults.FetchString(5, szNameSecond, sizeof szNameSecond);

			FormatTime(szTime, sizeof szTime, "%d/%m/%y - %T", hResults.FetchInt(6));
			FormatEx(szBuffer, sizeof szBuffer, "%s + %s [%s]", szNameFirst, szNameSecond, szTime);
			FormatEx(szInfo, sizeof szInfo, "%iћ%iћ%sћ%sћ%s", hResults.FetchInt(0), hResults.FetchInt(1), szNameFirst, szNameSecond, szTime);

			AddMenuItem(hMenu, szInfo, szBuffer);
		}

		SetMenuExitBackButton(hMenu, true);
		DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
	}
}

int CallBack_AdminMenu(Menu hMenu, MenuAction eAction, int iClient, int iItem)
{
	switch(eAction)
	{
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				Open_MainMenu(iClient);
			}
		}
		case MenuAction_Select:
		{
			char szInfo[512], szExplode[5][128];
			hMenu.GetItem(iItem, szInfo, sizeof szInfo);

			ExplodeString(szInfo, "ћ", szExplode, sizeof szExplode, sizeof szExplode[]);

			int iFirst = StringToInt(szExplode[0]);
			int iSecond = StringToInt(szExplode[1]);

			bool bFirst = false, bSecond = false;
			int iFirstID = -1, iSecondID = -1;

			for(int i = MaxClients + 1; --i;)
			{
				if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
				{
					int iAccountID = GetSteamAccountID(i);

					if(iFirst == iAccountID)
					{
						bFirst = true;
						iFirstID = GetClientUserId(i);
					}
					else if(iSecond == iAccountID)
					{
						bSecond = true;
						iSecondID = GetClientUserId(i);
					}
				}
			}

			Handle hMenu2 = CreateMenu(CallBack_DiluteMenu);

			FormatEx(szInfo, sizeof szInfo, "Развод пары: \nВ браке с: %s \n%s - %s \n%s - %s\n ", szExplode[4], szExplode[2], bFirst ? "Онлайн" : "Оффлайн", szExplode[3], bSecond ? "Онлайн" : "Оффлайн");
			SetMenuTitle(hMenu2, szInfo);

			FormatEx(szInfo, sizeof szInfo, "%iћ%bћ%iћ%iћ%bћ%iћ%sћ%s", iFirst, bFirst, iFirstID, iSecond, bSecond, iSecondID, szExplode[2], szExplode[3]);
			AddMenuItem(hMenu2, szInfo, "Развести");

			SetMenuExitBackButton(hMenu2, true);
			DisplayMenu(hMenu2, iClient, MENU_TIME_FOREVER);
		}
	}

	return 0;
}

int CallBack_DiluteMenu(Menu hMenu, MenuAction eAction, int iClient, int iItem)
{
	switch(eAction)
	{
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				Open_AdminMenu(iClient);
			}
		}
		case MenuAction_Select:
		{
			char szInfo[512], szQuery[512], szExplode[8][128];
			hMenu.GetItem(iItem, szInfo, sizeof szInfo);

			ExplodeString(szInfo, "ћ", szExplode, sizeof szExplode, sizeof szExplode[]);

			bool bFirst = view_as<bool>(StringToInt(szExplode[1]));
			bool bSecond = view_as<bool>(StringToInt(szExplode[4]));
			int iTarget;

			if(bFirst && (iTarget = GetClientOfUserId(StringToInt(szExplode[2]))) > 0 && IsClientInGame(iTarget))
			{
				PrintToChat(iTarget, "\x01[\x04Система\x01] \x04Администрация развела Вас с \x03%s", szExplode[7]);
			}
			if(bSecond && (iTarget = GetClientOfUserId(StringToInt(szExplode[5]))) > 0 && IsClientInGame(iTarget))
			{
				PrintToChat(iTarget, "\x01[\x04Система\x01] \x04Администрация развела Вас с \x03%s", szExplode[6]);
			}

			PrintToChat(iClient, "\x01[\x04Система\x01] \x03Вы развели \x04%s \x03с \x04%s", szExplode[6], szExplode[7]);

			FormatEx(szQuery, sizeof szQuery, DELETE_PAIR, StringToInt(szExplode[0]));
			g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery);

			FormatEx(szQuery, sizeof szQuery, DELETE_KILLS, StringToInt(szExplode[0]));
			g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery);

			FormatEx(szQuery, sizeof szQuery, DELETE_KILLS, StringToInt(szExplode[3]));
			g_hDatabase.Query(SQL_Callback_ErrorCheck, szQuery, 10);

			Open_MainMenu(iClient);
		}
	}

	return 0;
}

int CallBack_Panel(Menu hMenu, MenuAction eAction, int iClient, int iItem)
{
	if(eAction == MenuAction_Select && iItem == 8)
	{
		Open_MainMenu(iClient);
	}

	return 0;
}

void GetStringTime(int time, char[] buffer, int maxlength)
{
    static int dims[] = {60, 60, 24, 30, 12, cellmax};
    static char sign[][] = {"с", "м", "ч", "д", "м", "г"};
    static char form[][] = {"%02i%s%s", "%02i%s %s", "%i%s %s"};
    buffer[0] = EOS;
    int i = 0, f = -1;
    bool cond = false;

    while (!cond)
	{
        if (f++ == 1)
		{
            cond = true;
		}
        do
		{
            Format(buffer, maxlength, form[f], time % dims[i], sign[i], buffer);

            if (time /= dims[i++], time == 0)
			{
                return;
			}
        }
		while (cond);
    }
}

void SQL_Callback_ErrorCheck(Database hOwner, DBResultSet hResult, const char[] szError, int data)
{
	if(szError[0])
	{
		LogError("SQL_Callback_ErrorCheck: %s", szError);
	}

	if(data == 10)
	{
		for(int i = MaxClients + 1; --i;)
		{
			if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
			{
				LoadClient(i, GetSteamAccountID(i));
			}
		}
	}
}
