unit Atlas.IDE.Commands.EditorServer;

// Editorbefehle mit Anfrage an den Server (#399), Vorfahr von
// TAtlasIdeEditorCommands (Atlas.IDE.Commands.Editor, Beschreibung dort):
// qualifizierter Name (#128), Formatieren (#43), Unit ⇄ Testunit (#189) und die
// Schnellbefehle mit „/“ samt ///-Gerüsten (#293, #88).

interface

uses
  Atlas.Core.Lsp.WorkspaceEdits,
  ToolsAPI,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Editor.SlashTrigger,
  Atlas.IDE.Commands.EditorSelection;

type
  /// <summary>Editorbefehle mit Anfrage an den Server.</summary>
  TAtlasEditorServerCommands = class(TAtlasEditorSelectionCommands)
  protected
    /// <summary>Qualifizierter Name am Cursor (#128); False mit Meldung ohne Server oder Editor, True mit
    /// AName = '' ohne Symbol.</summary>
    class function FetchQualifiedName(AWithParameters: Boolean; out AName: string): Boolean; static;
    class procedure RunSlash(const AView: IOTAEditView; AKind: TAtlasSlashKind); static;
    /// <summary>Änderungen des Servers für den Schnellbefehl AKind an der Schreibmarke; False ohne.</summary>
    class function SlashEdits(const AView: IOTAEditView; AKind: TAtlasSlashKind; out AText: string;
      out AEdits: TArray<TLspTextEdit>): Boolean; static;
    /// <summary>///-Gerüst: Platzhalter-Modus bzw. Cursor in die Zusammenfassung.</summary>
    class procedure PlaceDocComment(const AView: IOTAEditView; const ABefore: string;
      const AEdit: TLspTextEdit); static;
  public
    class procedure CopyQualifiedName(AWithParameters: Boolean); static;
    /// <summary>Qualifizierter Name am Cursor der oberen Datei (ohne Parameter); False mit Meldung ohne Server,
    /// Editor oder Symbol.</summary>
    class function QualifiedNameHere(out AName: string): Boolean; static;
    /// <summary>Zur Testunit bzw. getesteten Unit der oberen Datei; legt eine fehlende Testunit an (#189).</summary>
    class procedure SwitchTestUnit; static;
    /// <summary>Obere Datei formatieren (#43): mit Auswahl nur deren Zeilen. Ausgeschaltet oder ohne Änderung eine
    /// Zeile in der Meldungsansicht.</summary>
    class procedure FormatCode; static;
    /// <summary>Nach jeder Änderung im Editor (Notifier): Schnellbefehle und ///-Gerüste auslösen.</summary>
    class procedure EditorModified(const AView: IOTAEditView); static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Editor.TestUnit,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Editor.WorkspaceEdit;

const
  // Beim Tippen: lieber nichts tun als die IDE aufhalten.
  cSlashTimeoutMs = 3000;
  cQualifiedNameCommand = 'atlas.server.qualifiedName';
  cTestUnitCommand = 'atlas.server.testUnit';

/// <summary>Änderungen AEdits an AFileName als ein Rückgängig-Schritt AUndo; Fehlertext oder ''.</summary>
function ApplyFileEdits(const AFileName: string; const AEdits: TArray<TLspTextEdit>; const AUndo: string): string;
var
  mEdit: TLspWorkspaceEdit;
begin
  mEdit := Default(TLspWorkspaceEdit);
  mEdit.Files := [Default(TLspFileEdits)];
  mEdit.Files[0].FileName := AFileName;
  mEdit.Files[0].Edits := AEdits;
  Result := TAtlasIdeWorkspaceEdit.Apply(mEdit, TAtlasUnopenedPolicy.WriteToDisk, AUndo).Error;
end;

/// <summary>Argumente von atlas.server.testUnit: URI der Datei und Zeile.</summary>
function TestUnitArguments(const AFileName: string; ALine: Integer): string;
var
  mValues: TJSONArray;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(AFileName));
    mValues.Add(ALine);
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

/// <summary>Antwort von atlas.server.testUnit gelesen: Gegenstück und gegebenenfalls das Edit zum Anlegen.</summary>
procedure ReadTestUnit(AAnswer: TJSONValue; out AInfo: TAtlasTestUnitInfo; out AEdit: TLspWorkspaceEdit);
begin
  AInfo := TAtlasTestUnitInfo.FromJson(AAnswer,
    function(AUri: string): string
    begin
      Result := TLspSession.UriToPath(AUri);
    end);
  AEdit := Default(TLspWorkspaceEdit);
  if (AAnswer is TJSONObject) and AInfo.CanCreate then
  begin
    AEdit := TLspWorkspaceEdit.FromJson(TJSONObject(AAnswer).GetValue('edit'));
  end;
end;

class function TAtlasEditorServerCommands.FetchQualifiedName(AWithParameters: Boolean; out AName: string): Boolean;
var
  mView: IOTAEditView;
  mFileName, mArguments: string;
  mLines: TArray<string>;
  mSelection: TLspRange;
  mValues: TJSONArray;
  mAnswer: TJSONValue;
begin
  AName := '';
  Result := False;
  if not Current(mView, mFileName, mLines, mSelection) then
  begin
    Exit;
  end;
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(mFileName));
    mValues.AddElement(TJSONObject.Create.AddPair('line', TJSONNumber.Create(mSelection.StartPos.Line))
      .AddPair('character', TJSONNumber.Create(mSelection.StartPos.Character)));
    mValues.AddElement(TJSONBool.Create(AWithParameters));
    mArguments := mValues.ToJSON;
  finally
    mValues.Free;
  end;
  try
    mAnswer := Session.RunCommand(cQualifiedNameCommand, mArguments, CommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  try
    if mAnswer is TJSONString then
    begin
      AName := mAnswer.Value;
    end;
    Result := True;
  finally
    mAnswer.Free;
  end;
end;

class function TAtlasEditorServerCommands.QualifiedNameHere(out AName: string): Boolean;
begin
  Result := FetchQualifiedName(False, AName) and (AName <> '');
end;

class procedure TAtlasEditorServerCommands.CopyQualifiedName(AWithParameters: Boolean);
var
  mName: string;
begin
  if not FetchQualifiedName(AWithParameters, mName) then
  begin
    Exit;
  end;
  if mName = '' then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  Clipboard.AsText := mName;
  Say(TAtlasStrings.Fmt(TAtlasTextId.EditorCopied, [mName]));
end;

class procedure TAtlasEditorServerCommands.FormatCode;
var
  mView: IOTAEditView;
  mFileName, mError: string;
  mLines: TArray<string>;
  mSelection: TLspRange;
  mIndent: Integer;
  mEdits: TArray<TLspTextEdit>;
begin
  if not TAtlasIdeSettings.Current.FormatCode then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.FormatCodeOff));
    Exit;
  end;
  if not Current(mView, mFileName, mLines, mSelection) then
  begin
    Exit;
  end;
  // Breite einer Ebene aus dem Editor; .editorconfig und atlas.json gehen beim Server vor.
  mIndent := TAtlasEditorBuffer.BlockIndent(mView.Buffer);
  try
    if mSelection.IsEmpty then
    begin
      mEdits := Session.Formatting(mFileName, mIndent, True, CommandTimeoutMs);
    end
    else
    begin
      mEdits := Session.Formatting(mFileName, mSelection, mIndent, True, CommandTimeoutMs);
    end;
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  if Length(mEdits) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.FormatCodeNothing));
    Exit;
  end;
  mError := ApplyFileEdits(mFileName, mEdits, TAtlasStrings.Text(TAtlasTextId.UndoActionFormat));
  if mError <> '' then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mError]));
  end;
end;

class procedure TAtlasEditorServerCommands.SwitchTestUnit;
var
  mView: IOTAEditView;
  mFileName, mArguments: string;
  mLines: TArray<string>;
  mSelection: TLspRange;
  mAnswer: TJSONValue;
  mInfo: TAtlasTestUnitInfo;
  mEdit: TLspWorkspaceEdit;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if not Current(mView, mFileName, mLines, mSelection) then
  begin
    Exit;
  end;
  mArguments := TestUnitArguments(mFileName, mSelection.StartPos.Line);
  try
    mAnswer := Session.RunCommand(cTestUnitCommand, mArguments, CommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  try
    ReadTestUnit(mAnswer, mInfo, mEdit);
  finally
    mAnswer.Free;
  end;
  if mInfo.CounterpartFile <> '' then
  begin
    TAtlasIdeNavigation.GoToLocation(mInfo.CounterpartFile, 0, 0);
  end
  else if not mInfo.CanCreate or mEdit.IsEmpty then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestUnitNone, [mInfo.Reason]));
  end
  else
  begin
    // Anlegen und ins Testprojekt eintragen (#274), dann öffnen.
    mOutcome := TAtlasIdeWorkspaceEdit.Apply(mEdit,
      TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
      TAtlasStrings.Fmt(TAtlasTextId.TestUnitLensCreate, [mInfo.Counterpart]));
    if mOutcome.Error <> '' then
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
    end
    else
    begin
      TAtlasIdeNavigation.GoToLocation(mInfo.NewFile, 0, 0);
    end;
  end;
end;

class procedure TAtlasEditorServerCommands.EditorModified(const AView: IOTAEditView);
var
  mCursor: TOTAEditPos;
  mLineText, mPrevious, mBefore, mKey: string;
  mKind: TAtlasSlashKind;
  mView: IOTAEditView;
begin
  if (AView = nil) or (AView.Buffer = nil) or not TAtlasIdeSettings.Current.Enabled or
    not TAtlasIdeSettings.Current.SlashCommands then
  begin
    Exit;
  end;
  mCursor := AView.CursorPos;
  mLineText := TAtlasEditorBuffer.LineText(AView, mCursor.Line);
  mBefore := Copy(mLineText, 1, TLspSession.ColumnToIndex(mLineText, mCursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer)));
  mPrevious := '';
  if mCursor.Line > 1 then
  begin
    mPrevious := TAtlasEditorBuffer.LineText(AView, mCursor.Line - 1);
  end;
  mKind := TAtlasSlashTrigger.Detect(mPrevious, mBefore);
  if mKind = TAtlasSlashKind.None then
  begin
    FLastSlash := '';
    Exit;
  end;
  mKey := TAtlasSlashTrigger.Key(AView.Buffer.FileName, mCursor.Line, mKind, mPrevious);
  if mKey = FLastSlash then
  begin
    Exit;
  end;
  FLastSlash := mKey;
  // Erst nach der Änderung, wenn die IDE den Cursor gesetzt hat; nie im Notifier.
  mView := AView;
  TAtlasMainThread.ForceQueue(TAtlasFeature.SlashCommands,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.SlashCommands,
        procedure
        begin
          RunSlash(mView, mKind);
        end);
    end);
end;

class function TAtlasEditorServerCommands.SlashEdits(const AView: IOTAEditView; AKind: TAtlasSlashKind;
  out AText: string; out AEdits: TArray<TLspTextEdit>): Boolean;
var
  mRunning: TLspSession;
  mFileName: string;
  mLines: TArray<string>;
  mLine, mCharacter: Integer;
begin
  Result := False;
  AText := '';
  AEdits := nil;
  mRunning := Session;
  if (mRunning = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  mFileName := AView.Buffer.FileName;
  AText := TAtlasEditorBuffer.Text(AView.Buffer);
  mRunning.Sync(mFileName, AText);
  mLines := AText.Split([#13#10, #10]);
  mLine := AView.CursorPos.Line - 1;
  if (mLine < 0) or (mLine >= Length(mLines)) then
  begin
    Exit;
  end;
  mCharacter := TLspSession.ColumnToIndex(mLines[mLine], AView.CursorPos.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  try
    AEdits := mRunning.OnTypeFormatting(mFileName, mLine, mCharacter, TAtlasSlashTrigger.TriggerChar(AKind),
      TLspFormatOptions.Create(TAtlasEditorBuffer.BlockIndent(AView.Buffer), True), cSlashTimeoutMs);
  except
    on E: ELspClientError do
    begin
      // Beim Tippen keine Meldung; nur ins Protokoll.
      TAtlasGuard.Log('Schnellbefehl: ' + TAtlasGuard.MessageText(E.Message));
      Exit;
    end;
  end;
  Result := Length(AEdits) > 0;
end;

class procedure TAtlasEditorServerCommands.PlaceDocComment(const AView: IOTAEditView; const ABefore: string;
  const AEdit: TLspTextEdit);
var
  mExpansion: TAtlasSnippetExpansion;
  mDocument: string;
begin
  // ///-Gerüst: Platzhalter-Modus über die Beschreibungen. Das Gerüst ist die erste Änderung; über einer
  // Methodenimplementierung steht es weiter oben, das Löschen der "///"-Zeile darunter verschiebt es nicht.
  mExpansion := TAtlasSlashTrigger.DocCommentExpansion(AEdit.NewText);
  if not mExpansion.HasPlaceholders then
  begin
    Exit;
  end;
  mDocument := TAtlasEditorBuffer.Text(AView.Buffer);
  if Assigned(FOnPlaceholders) then
  begin
    FOnPlaceholders(AView, ABefore, TAtlasEditorBuffer.CharOffset(mDocument, AEdit.StartPos.Line,
      AEdit.StartPos.Character), mExpansion);
    Exit;
  end;
  // Ohne Platzhalter-Modus: Cursor in die Zusammenfassung.
  AView.CursorPos := EditPos(mDocument.Split([#13#10, #10]), TLspTextPosition.Create(AEdit.StartPos.Line,
    AEdit.StartPos.Character + mExpansion.Stops[0].Start), TAtlasEditorBuffer.TabWidth(AView.Buffer));
  AView.Paint;
end;

class procedure TAtlasEditorServerCommands.RunSlash(const AView: IOTAEditView; AKind: TAtlasSlashKind);
var
  mText, mError: string;
  mEdits: TArray<TLspTextEdit>;
begin
  if not SlashEdits(AView, AKind, mText, mEdits) then
  begin
    Exit;
  end;
  mError := ApplyFileEdits(AView.Buffer.FileName, mEdits, TAtlasStrings.Text(TAtlasTextId.UndoActionSlash));
  if mError <> '' then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mError]));
  end
  else if AKind = TAtlasSlashKind.DocComment then
  begin
    PlaceDocComment(AView, mText, mEdits[0]);
  end;
end;

end.
