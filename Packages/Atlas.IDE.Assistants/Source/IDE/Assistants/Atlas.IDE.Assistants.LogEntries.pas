unit Atlas.IDE.Assistants.LogEntries;

// Einträge für das KI-Protokoll (#2049) aus Sicht der IDE: Zu einer Änderung kommt die Methode an der ersten
// geänderten Zeile aus der Gliederung, sofern die Datei im oberen Editor steht (wie „Weiterarbeiten“ und
// get_ide_context); sonst bleibt sie leer. Eingänge und zurückgehaltene Änderungen tragen ihre Einträge hierüber ein.

interface

uses
  Atlas.Core.Assistants.Log;

type
  TAtlasIdeLogEntries = class
  public
    /// <summary>Methode an ALine (ab 1) in AFileName, wenn die Datei im oberen Editor steht; sonst ''.</summary>
    class function MethodAt(const AFileName: string; ALine: Integer): string; static;
    /// <summary>Änderung von ABefore nach AAfter in ALog eintragen (mit Methode); liefert die Kennung, 0 ohne
    /// Protokoll.</summary>
    class function AddEdit(ALog: TAtlasAssistantsLog; AKind: TAtlasAssistantsLogKind;
      const AFileName, AClient, ABefore, AAfter: string): Integer; static;
    /// <summary>Eintrag ohne Änderung in ALog (Ablehnung, Build, Frage); ALog darf nil sein.</summary>
    class procedure AddPlain(ALog: TAtlasAssistantsLog; AKind: TAtlasAssistantsLogKind;
      const AFileName, AClient, ADetail: string); static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.StatusBar.Content,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Outline.Cache;

{ TAtlasIdeLogEntries }

class function TAtlasIdeLogEntries.MethodAt(const AFileName: string; ALine: Integer): string;
var
  mView: IOTAEditView;
  mSnapshot: TAtlasOutlineSnapshot;
  mMethod: TAtlasStatusMethod;
begin
  Result := '';
  if not TAtlasIdeOutlineCache.IsPascal(AFileName) then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.TopView;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, AFileName) then
  begin
    Exit;
  end;
  mSnapshot := TAtlasIdeOutlineCache.Refresh(mView);
  if (mSnapshot.Status = TAtlasOutlineStatus.Ready) and SameText(mSnapshot.FileName, AFileName) then
  begin
    mMethod := TAtlasStatusBarContent.MethodAt(mSnapshot.Nodes, ALine - 1, Default(TAtlasFileMetrics), False);
    if mMethod.Found then
    begin
      Result := mMethod.Name;
    end;
  end;
end;

class function TAtlasIdeLogEntries.AddEdit(ALog: TAtlasAssistantsLog; AKind: TAtlasAssistantsLogKind;
  const AFileName, AClient, ABefore, AAfter: string): Integer;
var
  mEntry: TAtlasAssistantsLogEntry;
begin
  if (ALog = nil) or not ALog.Enabled then
  begin
    Exit(0);
  end;
  mEntry := TAtlasAssistantsLog.EditEntry(AKind, AFileName, AClient, ABefore, AAfter);
  mEntry.Method := MethodAt(AFileName, mEntry.Change.FirstLine);
  Result := ALog.Add(mEntry);
end;

class procedure TAtlasIdeLogEntries.AddPlain(ALog: TAtlasAssistantsLog; AKind: TAtlasAssistantsLogKind;
  const AFileName, AClient, ADetail: string);
begin
  if ALog <> nil then
  begin
    ALog.Add(TAtlasAssistantsLog.PlainEntry(AKind, AFileName, AClient, ADetail));
  end;
end;

end.
