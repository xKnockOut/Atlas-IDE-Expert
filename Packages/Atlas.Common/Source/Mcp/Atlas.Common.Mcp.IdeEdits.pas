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

  /// <summary>Änderung einer Datei: erwarteter Inhalt des Puffers und neuer Text.</summary>
  TMcpIdeEdit = record
    FileName: string;
    Expected: string;
    Text: string;
    class function Make(const AFileName, AExpected, AText: string): TMcpIdeEdit; static;
  end;

  TMcpIdeEdits = class
  public const
    AnswerMs = 3000;
    TakenMs = 30000;
    /// <summary>Takt, in dem der Aufrufer von Send auf Antwort- und Übernahmedatei prüft (Code-Review P-16).</summary>
    PollMs = 50;
  public
    /// <summary>Eingang des IDE-Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function InboxOf(const ABase: string; APid: Cardinal): string; static;
    /// <summary>
    /// Schickt die Änderung AEdit (von Expected zu Text) an den Eingang AInbox und wartet auf das Plugin.
    /// AWait schläft kurz (Tests: übernimmt die Rolle des Plugins); AClock liefert Millisekunden.
    /// WriteYourself: Das Plugin hat den Auftrag nicht angenommen oder die Datei ist nicht mehr offen.
    /// Failed: abgelehnt (AReason), etwa weil der Puffer inzwischen geändert wurde.
    /// </summary>
    class function Send(const AInbox: string; const AEdit: TMcpIdeEdit; const AWait: TProc;
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

class function TMcpIdeEdit.Make(const AFileName, AExpected, AText: string): TMcpIdeEdit;
begin
  Result.FileName := AFileName;
  Result.Expected := AExpected;
  Result.Text := AText;
end;

function RequestText(const AEdit: TMcpIdeEdit): string;
var
  mJson: TJSONObject;
begin
  mJson := TJSONObject.Create;
  try
    mJson.AddPair('file', AEdit.FileName);
    mJson.AddPair('expected', AEdit.Expected);
    mJson.AddPair('text', AEdit.Text);
    Result := mJson.ToJSON;
  finally
    mJson.Free;
  end;
end;

/// <summary>Wartet höchstens AMs Millisekunden auf AAnswer; True, wenn sie da ist.</summary>
function AwaitAnswer(const AAnswer: string; AMs: Int64; const AWait: TProc; const AClock: TFunc<Int64>): Boolean;
var
  mStarted: Int64;
begin
  mStarted := AClock();
  while (AClock() - mStarted < AMs) and not FileExists(AAnswer) do
  begin
    AWait();
  end;
  Result := FileExists(AAnswer);
end;

/// <summary>Ergebnis aus der Antwortdatei des Plugins.</summary>
function OutcomeOf(const AAnswer: string; out AReason: string): TMcpIdeEditOutcome;
var
  mApplied, mNotOpen: Boolean;
begin
  if not ReadAnswer(AAnswer, mApplied, mNotOpen, AReason) then
  begin
    AReason := 'Antwort der IDE nicht lesbar.';
    Result := TMcpIdeEditOutcome.Failed;
  end
  else if mApplied then
  begin
    Result := TMcpIdeEditOutcome.Applied;
  end
  else if mNotOpen then
  begin
    Result := TMcpIdeEditOutcome.WriteYourself;
  end
  else
  begin
    Result := TMcpIdeEditOutcome.Failed;
  end;
end;

class function TMcpIdeEdits.Send(const AInbox: string; const AEdit: TMcpIdeEdit; const AWait: TProc;
  const AClock: TFunc<Int64>; out AReason: string): TMcpIdeEditOutcome;
var
  mId, mRequest, mAnswer: string;
begin
  AReason := '';
  mId := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
  mRequest := TPath.Combine(AInbox, mId + '.json');
  mAnswer := TPath.Combine(AInbox, mId + '.result.json');
  ForceDirectories(AInbox);
  TFile.WriteAllText(mRequest + '.tmp', RequestText(AEdit), TEncoding.UTF8);
  TFile.Move(mRequest + '.tmp', mRequest);
  if not AwaitAnswer(mAnswer, AnswerMs, AWait, AClock) then
  begin
    // Nicht übernommen: zurückziehen und selbst schreiben.
    if DeleteFile(mRequest) then
    begin
      Exit(TMcpIdeEditOutcome.WriteYourself);
    end;
    // Übernommen, aber noch nicht fertig.
    if not AwaitAnswer(mAnswer, TakenMs, AWait, AClock) then
    begin
      AReason := 'Die IDE hat die Änderung angenommen, aber nicht bestätigt.';
      Exit(TMcpIdeEditOutcome.Failed);
    end;
  end;
  Result := OutcomeOf(mAnswer, AReason);
end;

end.
