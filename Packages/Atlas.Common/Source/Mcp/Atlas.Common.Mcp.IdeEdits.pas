unit Atlas.Common.Mcp.IdeEdits;

// Schreibende MCP-Werkzeuge bei laufender IDE (#397): Ist eine Datei in einer
// IDE mit Atlas-Plugin offen, schreibt der MCP-Server sie nicht auf die
// Platte, sondern schickt die Änderung an den Eingang des Plugins
// (Protokoll: Atlas.Core.Files.EditInbox im Plugin):
//   1. <id>.json.tmp schreiben und in <id>.json umbenennen,
//   2. auf <id>.result.json warten,
//   3. nach dem Zeitlimit <id>.json löschen: Gelingt das, hat das Plugin den
//      Auftrag nie gesehen, und der MCP-Server schreibt selbst. Sonst hat das
//      Plugin ihn übernommen; dann wartet er länger auf das Ergebnis.
// Welche Dateien offen sind, steht unter "open" in editor-dirty-<pid>.json.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  TMcpIdeEditOutcome = (Applied, WriteYourself, Failed);

  TMcpIdeEdits = class
  public const
    AnswerMs = 3000;
    TakenMs = 30000;
  public
    /// <summary>Eingang des IDE-Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function InboxOf(const ABase: string; APid: Cardinal): string; static;
    /// <summary>
    /// Schickt die Änderung von AExpected zu AText an den Eingang AInbox und wartet auf das Plugin.
    /// AWait schläft kurz (Tests: übernimmt die Rolle des Plugins); AClock liefert Millisekunden.
    /// WriteYourself: Das Plugin hat den Auftrag nicht angenommen oder die Datei ist nicht mehr offen.
    /// Failed: abgelehnt (AReason), etwa weil der Puffer inzwischen geändert wurde.
    /// </summary>
    class function Send(const AInbox, AFileName, AExpected, AText: string; const AWait: TProc;
      const AClock: TFunc<Int64>; out AReason: string): TMcpIdeEditOutcome; static;
  end;

implementation

uses
  System.IOUtils,
  System.JSON;

class function TMcpIdeEdits.InboxOf(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-edits'), IntToStr(APid));
end;

function ReadAnswer(const AFileName: string; out AApplied, ANotOpen: Boolean; out AReason: string): Boolean;
var
  Text: string;
  Json: TJSONValue;
begin
  AApplied := False;
  ANotOpen := False;
  AReason := '';
  try
    Text := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  except
    on Exception do
      Exit(False);
  end;
  Json := TJSONObject.ParseJSONValue(Text);
  try
    Result := Json is TJSONObject;
    if Result then
    begin
      AApplied := TJSONObject(Json).GetValue<Boolean>('applied', False);
      ANotOpen := TJSONObject(Json).GetValue<Boolean>('notOpen', False);
      AReason := TJSONObject(Json).GetValue<string>('reason', '');
    end;
  finally
    Json.Free;
  end;
  try
    TFile.Delete(AFileName);
  except
    on Exception do
      ;
  end;
end;

class function TMcpIdeEdits.Send(const AInbox, AFileName, AExpected, AText: string; const AWait: TProc;
  const AClock: TFunc<Int64>; out AReason: string): TMcpIdeEditOutcome;
var
  Id, Request, Answer, Text: string;
  Json: TJSONObject;
  Started: Int64;
  WasApplied, NotOpen: Boolean;
begin
  AReason := '';
  Id := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
  Request := TPath.Combine(AInbox, Id + '.json');
  Answer := TPath.Combine(AInbox, Id + '.result.json');
  Json := TJSONObject.Create;
  try
    Json.AddPair('file', AFileName);
    Json.AddPair('expected', AExpected);
    Json.AddPair('text', AText);
    Text := Json.ToJSON;
  finally
    Json.Free;
  end;
  ForceDirectories(AInbox);
  TFile.WriteAllText(Request + '.tmp', Text, TEncoding.UTF8);
  TFile.Move(Request + '.tmp', Request);
  Started := AClock();
  while AClock() - Started < AnswerMs do
  begin
    if FileExists(Answer) then
      Break;
    AWait();
  end;
  if not FileExists(Answer) then
  begin
    // Nicht übernommen: zurückziehen und selbst schreiben.
    if DeleteFile(Request) then
      Exit(TMcpIdeEditOutcome.WriteYourself);
    // Übernommen, aber noch nicht fertig.
    Started := AClock();
    while (AClock() - Started < TakenMs) and not FileExists(Answer) do
      AWait();
    if not FileExists(Answer) then
    begin
      AReason := 'Die IDE hat die Änderung angenommen, aber nicht bestätigt.';
      Exit(TMcpIdeEditOutcome.Failed);
    end;
  end;
  if not ReadAnswer(Answer, WasApplied, NotOpen, AReason) then
  begin
    AReason := 'Antwort der IDE nicht lesbar.';
    Exit(TMcpIdeEditOutcome.Failed);
  end;
  if WasApplied then
    Result := TMcpIdeEditOutcome.Applied
  else if NotOpen then
    Result := TMcpIdeEditOutcome.WriteYourself
  else
    Result := TMcpIdeEditOutcome.Failed;
end;

end.
