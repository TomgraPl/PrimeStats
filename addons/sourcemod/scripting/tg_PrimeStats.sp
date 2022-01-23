/*
			\\\\\///CHANGELOG\\\/////

	1.0.0 - Pierwsze wydanie pluginu
	1.0.1 - Usunięto zapisywanie nicku do bazy danych, ustawiono domyślnie -1 lda statusuPrime (w celu usunięcia fałszywych nonPrime'ów w przypadku, kiedy gracz spędzi na serwerze mniej niż minutę)
	1.1.0 - Dodano komendę sm_primestats, która podsumowuje dane zbierane przez plugin

*/


public Plugin myinfo =
{
	name = "tg_PrimeStats",
	author = "Tomgra",
	description = "Plugin zapisuje, czy dany gracz posiada Prime'a oraz jego czas gry",
	version = "1.1.0",
	url = "https://steamcommunity.com/id/tomgra/"
};

#include <sourcemod>
#include <sdktools.inc>
#define TABLE "tg_PrimeStats"
#define sTAG "» PS_SQL"
Database DB;
int primeStatus[MAXPLAYERS+1]=-1, playTime[MAXPLAYERS+1];

public void OnPluginStart()
{
	RegAdminCmd("sm_primestats", sm_PrimeStats, ADMFLAG_ROOT, "Komenda wyświetla na chacie podsumowanie statystyk zbieranych przez plugin");
	HookEvent("cs_win_panel_match", Event_MapEnd);
}

public void OnMapStart()
{
	DataBaseConnect();
}
public Action Event_MapEnd(Event event, char[] name, bool dontBroadcast)
{
	SaveData();
}
public void OnClientPutInServer(int client)
{
	if(!IsValidClient(client)) return;
	primeStatus[client]=0;
	playTime[client]=0;
}
public void OnClientPostAdminCheck(int client)
{
	if(!IsValidClient(client)) return;
	int id=GetClientUserId(client);
	CreateTimer(60.0, Timer_Client, id, TIMER_REPEAT);
	DataBaseRead(client);
	if(primeStatus[client]<1)
		primeStatus[client]=GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_nPersonaDataPublicLevel", _, client)
}
public void OnClientDisconnect(int client)
{
	if(!IsValidClient(client)) return;
	DataBaseWrite(client);
}
public Action Timer_Client(Handle timer, int id)
{
	if(!GetClientOfUserId(id)) return Plugin_Stop;
	int client=GetClientOfUserId(id);
	if(!IsValidClient(client)) return Plugin_Stop;
	if(primeStatus[client]<0)
		primeStatus[client]=GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_nPersonaDataPublicLevel", _, client)
	playTime[client]++;
	return Plugin_Continue;
}




public Action sm_PrimeStats(int client, int args)
{
	if(client!=0&&!IsRoot(client)) return Plugin_Handled;
		
	char buffer[1024];
	Format(buffer, sizeof(buffer), "SELECT `primeStatus`, `playTime` FROM `%s` WHERE `primeStatus`>=0;", TABLE);
	DBResultSet query=SQL_Query(DB, buffer);
	if(query==null)
	{
		char error[255];
		SQL_GetError(DB, error, sizeof(error));
		PrintToServer("%s Nie udało się pobrać danych! (error: %s)", sTAG, error);
		return Plugin_Handled;
	}
	int totalTime, rowTime, rowStatus, primeTime, count, primeCount;
	while(SQL_FetchRow(query))
	{
		rowStatus=SQL_FetchInt(query, 0);
		rowTime=SQL_FetchInt(query, 1);
		totalTime+=rowTime;
		count++;
		if(rowStatus>0)
		{
			primeTime+=rowTime;
			primeCount++;
		}
	}
	int percent1=RoundToNearest(100.0-100*primeCount/count);
	int percent2=RoundToNearest(100.0-100*primeTime/totalTime);
	if(client>0)
		PrintToChat(client, "%s Gracze bez statusu Prime stanowią %d%s graczy. Ich czas gry stanowi %d%s całego czasu przegranego na serwerze. Łącznie na twoim serwerze zagrało %d różnych graczy.", sTAG, percent1, "%", percent2, "%", count);
	else if(client==0)
		PrintToServer("%s Gracze bez statusu Prime stanowia %d%s graczy. Ich czas gry stanowi %d%s calego czasu przegranego na serwerze. Lacznie na twoim serwerze zagralo %d roznych graczy.", sTAG, percent1, "%", percent2, "%", count);
	return Plugin_Handled;
}
public void DataBaseConnect()
{
	char buffer[1024];
	DB=SQL_Connect(TABLE, true, buffer, sizeof(buffer));
	if(DB==INVALID_HANDLE)
	{
		LogError("%s Nie udało się polaczyc! Error: %s", sTAG, buffer);
		return;
	}

	Format(buffer, sizeof(buffer), "CREATE TABLE IF NOT EXISTS `%s`(`steamid` INT NOT NULL PRIMARY KEY, `PrimeStatus` INT NOT NULL, `PlayTime` INT NOT NULL);", TABLE);
	if(!SQL_FastQuery(DB, buffer))
	{
		SQL_GetError(DB, buffer, sizeof(buffer));
		PrintToServer("%s Nie udało się stworzyc tabeli! Error: %s", sTAG, buffer);
	}
}
public void DataBaseRead(int client)
{
	if(!IsValidClient(client)) return;

	int sid=GetSteamAccountID(client);
	char buffer[1024];
	Format(buffer, sizeof(buffer), "SELECT `PrimeStatus`, `PlayTime` FROM `%s` WHERE `steamid`=%d;", TABLE, sid);
	DBResultSet query=SQL_Query(DB, buffer);
	if(query==null)
	{
		char error[255];
		SQL_GetError(DB, error, sizeof(error));
		PrintToServer("%s Nie udało się pobrać danych gracza %N! (error: %s)", sTAG, client, error);
		return;
	}
	if(!SQL_GetRowCount(query))
	{
		Format(buffer, sizeof(buffer), "INSERT INTO `%s` VALUES(%d, '-1', '0');", TABLE, sid);
		DBResultSet query2=SQL_Query(DB, buffer);
		if(query2==null)
		{
			char error[255];
			SQL_GetError(DB, error, sizeof(error));
			PrintToServer("%s Nie udało się dodac nowego gracza %N! (error: %s)", sTAG, client, error);
			return;
		}
		return;
	}
	SQL_FetchRow(query);
	primeStatus[client]=SQL_FetchInt(query, 0);
	playTime[client]=SQL_FetchInt(query, 1);
}
public void DataBaseWrite(int client)
{
	if(!IsValidClient(client)) return;

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	char name2[(sizeof(name)*2)+1];
	SQL_EscapeString(DB, name, name2, sizeof(name2));

	char buffer[1024];
	Format(buffer, sizeof(buffer), "UPDATE `%s` SET `PrimeStatus`=%d, `PlayTime`=%d  WHERE `steamid`=%d;", TABLE, primeStatus[client], playTime[client], GetSteamAccountID(client));
	if(!SQL_FastQuery(DB, buffer))
	{
		char error[255];
		SQL_GetError(DB, error, sizeof(error));
		PrintToServer("%s Nie udało się zaktualizować danych gracza %N! (error: %s)", sTAG, client, error);
	}
}
public void SaveData()
{
	for(int i=1; i<=MaxClients; i++)
	{
		if(!IsValidClient(i)) continue;
		DataBaseWrite(i);
	}
}


public bool IsValidClient(int client)
{
	if(client<= 0) return false;
	if(client>MaxClients) return false;
	if(!IsClientConnected(client)) return false;
	if(IsFakeClient(client)) return false;
	if(IsClientSourceTV(client)) return false;
	return IsClientInGame(client);
}
public bool IsRoot(int client)
{
	if(GetUserFlagBits(client) & ADMFLAG_ROOT)
		return true;

	return false;
}
