unit Atlas.IDE.Editor.InlineAccessor;

// Code-Aktionen „Zugriffsmethode durch Feld ersetzen“ und die Sammelaktionen
// für Unit und Projekt (#717): Der Server bietet sie als Client-Befehl
// atlas.inlineAccessor mit URI, Position und Bereich. Atlas schickt die
// offenen Puffer, holt das WorkspaceEdit (atlas.server.inlineAccessor), zeigt
// die Vorschau wie beim Umbenennen mit den Hinweisen des Servers (Methoden,
// die wegen Aufrufen bleiben) und übernimmt erst nach Bestätigung, je Datei
// ein Rückgängig-Schritt. Abschaltbar über refactoring.inlineAccessor (und
// refactoring.inlineAccessorBulk für die Sammelaktionen): Dann bietet der
// Server die Aktionen nicht an. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan;

type
  TAtlasIdeInlineAccessor = class
  public const
    ClientCommand = 'atlas.inlineAccessor';
  public
    /// <summary>AArgumentsJson: Argumente der Code-Aktion ([uri, position, scope]); ASession: laufende Sitzung oder
    /// nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Execute(ASession: TLspSession; const AArgumentsJson: string; APolicy: TAtlasUnopenedPolicy;
      const AMessage: TProc<string>); static;
  end;

implementation

uses
  System.JSON,
  Atlas.UI.Strings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.ServerEdit;

const
  ApplyCommand = 'atlas.server.inlineAccessor';
  // Aufrufe im Projekt suchen dauert, die Sammelaktion über das Projekt erst recht.
  TimeoutMs = 120000;

class procedure TAtlasIdeInlineAccessor.Execute(ASession: TLspSession; const AArgumentsJson: string;
  APolicy: TAtlasUnopenedPolicy; const AMessage: TProc<string>);
var
  mCommand: TAtlasServerEditCommand;
  mReply: TAtlasServerEditReply;
  mAccessors: Integer;
  mHint: string;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if ASession = nil then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  // Die Argumente der Code-Aktion gehen unverändert an den Server.
  mCommand.Command := ApplyCommand;
  mCommand.Arguments := AArgumentsJson;
  mCommand.TimeoutMs := TimeoutMs;
  mCommand.Failed := TAtlasTextId.InlineAccessorFailed;
  mAccessors := 0;
  if not TAtlasIdeServerEdit.Fetch(ASession, mCommand,
    procedure(const AReply: TJSONObject)
    begin
      mAccessors := TAtlasIdeServerEdit.NumberOf(AReply, 'accessors');
    end, AMessage, mReply) then
  begin
    Exit;
  end;
  if mReply.Edit.IsEmpty then
  begin
    AMessage(TAtlasStrings.Text(TAtlasTextId.InlineAccessorNothing));
    Exit;
  end;
  mHint := TAtlasStrings.Fmt(TAtlasTextId.InlineAccessorPreviewHint, [mAccessors, mReply.Edit.EditCount,
    Length(mReply.Edit.Files)]) + TAtlasIdeServerEdit.WarningLines(mReply, TAtlasTextId.InlineAccessorWarning);
  if TAtlasIdeServerEdit.Confirm(TAtlasStrings.Text(TAtlasTextId.InlineAccessorTitle), mHint,
    TAtlasStrings.Text(TAtlasTextId.InlineAccessorApply), mReply.Edit) and
    TAtlasIdeServerEdit.Apply(mReply.Edit, APolicy, TAtlasStrings.Text(TAtlasTextId.InlineAccessorTitle), AMessage,
    mOutcome) then
  begin
    AMessage(TAtlasStrings.Fmt(TAtlasTextId.InlineAccessorDone, [mAccessors, mOutcome.Edits, mOutcome.Files]));
    TAtlasIdeServerEdit.ReportAfter(mReply, mOutcome, TAtlasTextId.InlineAccessorWarning, AMessage);
  end;
end;

end.
