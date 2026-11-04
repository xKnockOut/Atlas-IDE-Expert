unit Atlas.IDE.Editor.ServerEdit;

// Gemeinsamer Ablauf der Code-Aktionen, die ein WorkspaceEdit vom Server
// holen (Umwandlungen, Verschieben, Extrahieren, Zugriffsmethoden …): offene
// Puffer schicken, Server-Befehl ausführen und {"edit", "warnings", …} lesen,
// Vorschau wie beim Umbenennen, nach Bestätigung übernehmen (je Datei ein
// Rückgängig-Schritt) und das Ergebnis melden. Früher stand jeder Schritt in
// jeder Aktion von Hand; die Aktionen behalten nur ihre Texte und die Werte,
// die nur sie lesen.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.UI.Strings,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.IDE.Editor.WorkspaceEdit;

type
  /// <summary>Server-Befehl mit seinen Argumenten, der Wartezeit und dem Text bei Fehlschlag (%s: Fehler des
  /// Servers).</summary>
  TAtlasServerEditCommand = record
    Command: string;
    Arguments: string;
    TimeoutMs: Integer;
    Failed: TAtlasTextId;
  end;

  /// <summary>Was alle Antworten tragen: die Änderung und die Warnungen.</summary>
  TAtlasServerEditReply = record
    Edit: TLspWorkspaceEdit;
    Warnings: TArray<string>;
  end;

  /// <summary>Liest weitere Werte aus der Antwort des Servers, solange sie lebt.</summary>
  TAtlasServerEditRead = reference to procedure(const AReply: TJSONObject);

  TAtlasIdeServerEdit = class
  public
    /// <summary>Schickt die offenen Puffer und führt ACommand aus; ARead (darf nil sein) liest weitere Werte. False,
    /// wenn der Server scheitert: Dann steht ACommand.Failed mit dessen Fehler in AMessage.</summary>
    class function Fetch(ASession: TLspSession; const ACommand: TAtlasServerEditCommand;
      const ARead: TAtlasServerEditRead; const AMessage: TProc<string>; out AReply: TAtlasServerEditReply): Boolean;
      static;
    /// <summary>Zahl AName aus AReply, sonst 0.</summary>
    class function NumberOf(const AReply: TJSONObject; const AName: string): Integer; static;
    /// <summary>Text AName aus AReply, sonst ''.</summary>
    class function TextOf(const AReply: TJSONObject; const AName: string): string; static;
    /// <summary>Je Warnung von AReply eine Zeile AWarning (%s), jede mit Zeilenumbruch davor.</summary>
    class function WarningLines(const AReply: TAtlasServerEditReply; AWarning: TAtlasTextId): string; static;
    /// <summary>Vorschau wie beim Umbenennen; True, wenn der Benutzer mit AApply übernimmt.</summary>
    class function Confirm(const ATitle, AHint, AApply: string; const AEdit: TLspWorkspaceEdit): Boolean; static;
    /// <summary>Übernimmt AEdit als Aktion AAction; False mit Meldung in AMessage, wenn nichts geändert wurde.
    /// </summary>
    class function Apply(const AEdit: TLspWorkspaceEdit; APolicy: TAtlasUnopenedPolicy; const AAction: string;
      const AMessage: TProc<string>; out AOutcome: TAtlasWorkspaceEditResult): Boolean; static;
    /// <summary>Nach dem Übernehmen: je Warnung eine Zeile AWarning (%s), dann die direkt geschriebenen Dateien.
    /// </summary>
    class procedure ReportAfter(const AReply: TAtlasServerEditReply; const AOutcome: TAtlasWorkspaceEditResult;
      AWarning: TAtlasTextId; const AMessage: TProc<string>); static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Results.Model,
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Foundation.Navigation;

/// <summary>Liest Änderung und Warnungen aus AAnswer (darf nil oder kein Objekt sein), dann ARead.</summary>
function ReadReply(const AAnswer: TJSONValue; const ARead: TAtlasServerEditRead): TAtlasServerEditReply;
var
  mReply: TJSONObject;
  mItem: TJSONValue;
begin
  Result.Edit := TLspWorkspaceEdit.FromJson(nil);
  Result.Warnings := nil;
  if not (AAnswer is TJSONObject) then
  begin
    Exit;
  end;
  mReply := TJSONObject(AAnswer);
  Result.Edit := TLspWorkspaceEdit.FromJson(mReply.GetValue('edit'));
  if mReply.GetValue('warnings') is TJSONArray then
  begin
    for mItem in TJSONArray(mReply.GetValue('warnings')) do
    begin
      Result.Warnings := Result.Warnings + [mItem.Value];
    end;
  end;
  if Assigned(ARead) then
  begin
    ARead(mReply);
  end;
end;

{ TAtlasIdeServerEdit }

class function TAtlasIdeServerEdit.Fetch(ASession: TLspSession; const ACommand: TAtlasServerEditCommand;
  const ARead: TAtlasServerEditRead; const AMessage: TProc<string>; out AReply: TAtlasServerEditReply): Boolean;
var
  mAnswer: TJSONValue;
begin
  Result := False;
  AReply := Default(TAtlasServerEditReply);
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  try
    mAnswer := ASession.RunCommand(ACommand.Command, ACommand.Arguments, ACommand.TimeoutMs);
    try
      AReply := ReadReply(mAnswer, ARead);
    finally
      mAnswer.Free;
    end;
    Result := True;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(ACommand.Failed, [E.Message]));
    end;
  end;
end;

class function TAtlasIdeServerEdit.NumberOf(const AReply: TJSONObject; const AName: string): Integer;
begin
  Result := 0;
  if (AReply <> nil) and (AReply.GetValue(AName) is TJSONNumber) then
  begin
    Result := TJSONNumber(AReply.GetValue(AName)).AsInt;
  end;
end;

class function TAtlasIdeServerEdit.TextOf(const AReply: TJSONObject; const AName: string): string;
begin
  Result := '';
  if (AReply <> nil) and (AReply.GetValue(AName) is TJSONString) then
  begin
    Result := AReply.GetValue(AName).Value;
  end;
end;

class function TAtlasIdeServerEdit.WarningLines(const AReply: TAtlasServerEditReply; AWarning: TAtlasTextId): string;
var
  mWarning: string;
begin
  Result := '';
  for mWarning in AReply.Warnings do
  begin
    Result := Result + sLineBreak + TAtlasStrings.Fmt(AWarning, [mWarning]);
  end;
end;

class function TAtlasIdeServerEdit.Confirm(const ATitle, AHint, AApply: string; const AEdit: TLspWorkspaceEdit):
  Boolean;
var
  mPreview: TArray<TAtlasResultEntry>;
  mOpen: TAtlasResultsOpen;
begin
  mPreview := TAtlasResults.RenamePreview(AEdit,
    function(const AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end);
  mOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
    end;
  Result := TAtlasRenamePreview.Execute(ATitle, AHint, AApply, TAtlasResults.Group(mPreview), mOpen);
end;

class function TAtlasIdeServerEdit.Apply(const AEdit: TLspWorkspaceEdit; APolicy: TAtlasUnopenedPolicy;
  const AAction: string; const AMessage: TProc<string>; out AOutcome: TAtlasWorkspaceEditResult): Boolean;
begin
  AOutcome := TAtlasIdeWorkspaceEdit.Apply(AEdit, APolicy, AAction);
  Result := AOutcome.Error = '';
  if not Result then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [AOutcome.Error]));
  end;
end;

class procedure TAtlasIdeServerEdit.ReportAfter(const AReply: TAtlasServerEditReply;
  const AOutcome: TAtlasWorkspaceEditResult; AWarning: TAtlasTextId; const AMessage: TProc<string>);
var
  mWarning: string;
begin
  for mWarning in AReply.Warnings do
  begin
    AMessage(TAtlasStrings.Fmt(AWarning, [mWarning]));
  end;
  if AOutcome.Written > 0 then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.EditWritten, [AOutcome.Written]));
  end;
end;

end.
