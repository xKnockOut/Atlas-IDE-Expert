unit Atlas.Core.Assistants.Inbox;

// Eingang des Plugins für Aufträge des MCP-Servers, ohne Open Tools API. Der
// Server legt je Auftrag <id>.json in einen Ordner (Bearbeiten:
// Atlas.Core.Assistants.EditInbox, Bauen: Atlas.Core.Assistants.BuildInbox);
// das Plugin übernimmt ihn durch Umbenennen in <id>.taken (wer das Umbenennen
// gewinnt, hat ihn; der Server zieht ihn nach seiner Frist sonst zurück) und
// antwortet mit <id>.result.json. Hier steht, was beide Eingänge gleich tun:
// wartende Aufträge finden, übernehmen und die Antwort schreiben. Was im
// Auftrag und in der Antwort steht, regeln die beiden Eingänge selbst.

interface

uses
  System.SysUtils;

type
  TAtlasFileInbox = class
  public const
    cRequestExtension = '.json';
    cTakenExtension = '.taken';
    cResultSuffix = '.result.json';
  public
    /// <summary>Wartende Aufträge in AFolder (ohne .tmp, .taken und Ergebnisse), älteste zuerst; leer ohne
    /// Ordner.</summary>
    class function Pending(const AFolder: string): TArray<string>; static;
    /// <summary>Übernimmt den Auftrag AFileName (Umbenennen in .taken) und liest seinen Text; AId ist der Name
    /// ohne Endung. False, wenn ihn schon jemand hat; unlesbar ergibt True mit leerem AText.</summary>
    class function Claim(const AFileName: string; out AId, AText: string): Boolean; static;
    /// <summary>Antwort AText als AId.result.json in AFolder (erst daneben, dann umbenennen) und den übernommenen
    /// Auftrag löschen.</summary>
    class procedure Answer(const AFolder, AId, AText: string); static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.Generics.Collections;

{ TAtlasFileInbox }

class function TAtlasFileInbox.Pending(const AFolder: string): TArray<string>;
var
  mName: string;
  mFound: TList<string>;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  mFound := TList<string>.Create;
  try
    for mName in TDirectory.GetFiles(AFolder, '*' + cRequestExtension) do
    begin
      if mName.EndsWith(cRequestExtension, True) and not mName.EndsWith(cResultSuffix, True) then
      begin
        mFound.Add(mName);
      end;
    end;
    mFound.Sort;
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

class function TAtlasFileInbox.Claim(const AFileName: string; out AId, AText: string): Boolean;
var
  mTaken: string;
begin
  AId := ChangeFileExt(ExtractFileName(AFileName), '');
  AText := '';
  mTaken := ChangeFileExt(AFileName, cTakenExtension);
  // Umbenennen ist der Zuschlag: Hat der MCP-Server inzwischen zurückgezogen, schlägt es fehl.
  Result := RenameFile(AFileName, mTaken);
  if not Result then
  begin
    Exit;
  end;
  try
    AText := TFile.ReadAllText(mTaken, TEncoding.UTF8);
  except
    on Exception do
      AText := '';
  end;
end;

class procedure TAtlasFileInbox.Answer(const AFolder, AId, AText: string);
var
  mTarget, mTemporary, mTaken: string;
begin
  mTarget := TPath.Combine(AFolder, AId + cResultSuffix);
  mTemporary := mTarget + '.tmp';
  TFile.WriteAllText(mTemporary, AText, TEncoding.UTF8);
  if FileExists(mTarget) then
  begin
    TFile.Delete(mTarget);
  end;
  TFile.Move(mTemporary, mTarget);
  mTaken := TPath.Combine(AFolder, AId + cTakenExtension);
  if FileExists(mTaken) then
  begin
    TFile.Delete(mTaken);
  end;
end;

end.
