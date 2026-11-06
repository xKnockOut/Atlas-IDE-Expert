unit Atlas.IDE.Commands.EditorServer;

// Editorbefehle mit Anfrage an den Server (#399), Vorfahr von
// TAtlasIdeEditorCommands (Atlas.IDE.Commands.Editor, Beschreibung dort):
// qualifizierter Name (#128), Formatieren (#43), Unit ⇄ Testunit (#189) und die
// Schnellbefehle mit „/“ samt ///-Gerüsten (#293, #88).
// Die Schnellbefehle fragen im Hintergrund (TAtlasBackgroundRequest): Die
// Diagnose vom 06.11.2026 zeigte Hänger bis 3 s, solange der Hauptthread auf
// onTypeFormatting wartete. Die Antwort gilt nur für den unveränderten Text
// (TAtlasSlashTrigger.StillValid); wurde weitergetippt, verfällt sie.
// Ebenso Unit ⇄ Testunit: Ein Klick auf die Code Lens hielt die IDE 9 s an,
// solange atlas.server.testUnit lief; jetzt öffnet die Antwort das Ziel.

interface

uses
  Atlas.Core.Lsp.WorkspaceEdits,
  ToolsAPI,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.BackgroundRequest,
  Atlas.Core.Editor.SlashTrigger,
  Atlas.Core.Editor.TestUnit,
  Atlas.IDE.Commands.EditorSelection;

type
  /// <summary>Editorbefehle mit Anfrage an den Server.</summary>
  TAtlasEditorServerCommands = class(TAtlasEditorSelectionCommands)
  protected class var
    /// <summary>Anfrage der Schnellbefehle; gibt TAtlasIdeEditorCommands.Uninstall frei.</summary>
    FSlashRequest: TAtlasBackgroundRequest;
    /// <summary>Anfrage von „Zur Testunit wechseln“; gibt TAtlasIdeEditorCommands.Uninstall frei.</summary>
    FTestUnitRequest: TAtlasBackgroundRequest;
  protected
    /// <summary>Qualifizierter Name am Cursor (#128); False mit Meldung ohne Server oder Editor, True mit
    /// AName = '' ohne Symbol.</summary>
    class function FetchQualifiedName(AWithParameters: Boolean; out AName: string): Boolean; static;
    /// <summary>Fragt den Server im Hintergrund nach den Änderungen für den Schnellbefehl AKind an der
    /// Schreibmarke; läuft noch eine Anfrage, darf die nächste Änderung erneut auslösen.</summary>
    class procedure RunSlash(const AView: IOTAEditView; AKind: TAtlasSlashKind); static;
    /// <summary>Antwort AEdits für AFileName mit Text AText; nur, wenn der Text der Ansicht unverändert ist.</summary>
    class procedure SlashAnswered(const AView: IOTAEditView; AKind: TAtlasSlashKind; const AFileName, AText: string;
      const AEdits: TArray<TLspTextEdit>); static;
    /// <summary>Antwort von atlas.server.testUnit: Gegenstück öffnen bzw. anlegen und öffnen.</summary>
    class procedure TestUnitAnswered(const AInfo: TAtlasTestUnitInfo; const AEdit: TLspWorkspaceEdit); static;
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
  Atlas.Core.Editor.FormatLog,
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

/// <summary>Protokoll vor dem Formatieren (anonym): Block der IDE und gesendeter Bereich.</summary>
procedure LogFormatRequest(const AView: IOTAEditView; const ASelection: TLspRange);
var
  mBlock: IOTAEditBlock;
  mValid: Boolean;
  mSize: Integer;
begin
  mBlock := AView.Block;
  mValid := (mBlock <> nil) and mBlock.IsValid;
  mSize := 0;
  if mValid then
  begin
    mSize := mBlock.Size;
  end;
  TAtlasGuard.Log(TAtlasFormatLog.Request(mValid, mSize, ASelection));
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
  LogFormatRequest(mView, mSelection);
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
  TAtlasGuard.Log(TAtlasFormatLog.Answer(mEdits, mSelection));
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
  mRunning: TLspSession;
  mInfo: TAtlasTestUnitInfo;
  mEdit: TLspWorkspaceEdit;
begin
  if not Current(mView, mFileName, mLines, mSelection) then
  begin
    Exit;
  end;
  mRunning := Session;
  if mRunning = nil then
  begin
    Exit;
  end;
  if FTestUnitRequest = nil then
  begin
    FTestUnitRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.EditorCommands);
  end;
  // Ein zweiter Klick, solange die erste Antwort aussteht, öffnet nichts doppelt.
  if FTestUnitRequest.Busy then
  begin
    Exit;
  end;
  mArguments := TestUnitArguments(mFileName, mSelection.StartPos.Line);
  mInfo := Default(TAtlasTestUnitInfo);
  mEdit := Default(TLspWorkspaceEdit);
  FTestUnitRequest.Start(
    procedure
    var
      mAnswer: TJSONValue;
    begin
      mAnswer := mRunning.RunCommand(cTestUnitCommand, mArguments, CommandTimeoutMs);
      try
        ReadTestUnit(mAnswer, mInfo, mEdit);
      finally
        mAnswer.Free;
      end;
    end,
    procedure(AOk: Boolean; const AError: string)
    begin
      if not AOk then
      begin
        Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [AError]));
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          TestUnitAnswered(mInfo, mEdit);
        end);
    end);
end;

class procedure TAtlasEditorServerCommands.TestUnitAnswered(const AInfo: TAtlasTestUnitInfo;
  const AEdit: TLspWorkspaceEdit);
var
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if AInfo.CounterpartFile <> '' then
  begin
    TAtlasIdeNavigation.GoToLocation(AInfo.CounterpartFile, 0, 0);
  end
  else if not AInfo.CanCreate or AEdit.IsEmpty then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestUnitNone, [AInfo.Reason]));
  end
  else
  begin
    // Anlegen und ins Testprojekt eintragen (#274), dann öffnen.
    mOutcome := TAtlasIdeWorkspaceEdit.Apply(AEdit,
      TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
      TAtlasStrings.Fmt(TAtlasTextId.TestUnitLensCreate, [AInfo.Counterpart]));
    if mOutcome.Error <> '' then
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
    end
    else
    begin
      TAtlasIdeNavigation.GoToLocation(AInfo.NewFile, 0, 0);
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

class procedure TAtlasEditorServerCommands.RunSlash(const AView: IOTAEditView; AKind: TAtlasSlashKind);
var
  mRunning: TLspSession;
  mFileName, mText, mTrigger: string;
  mLines: TArray<string>;
  mLine, mCharacter: Integer;
  mOptions: TLspFormatOptions;
  mView: IOTAEditView;
  mKind: TAtlasSlashKind;
  mEdits: TArray<TLspTextEdit>;
begin
  mRunning := Session;
  if (mRunning = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  if FSlashRequest = nil then
  begin
    FSlashRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.SlashCommands);
  end;
  if FSlashRequest.Busy then
  begin
    // Nicht verschluckt: Die nächste Änderung an dieser Stelle fragt erneut.
    FLastSlash := '';
    Exit;
  end;
  mFileName := AView.Buffer.FileName;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mRunning.Sync(mFileName, mText);
  mLines := mText.Split([#13#10, #10]);
  mLine := AView.CursorPos.Line - 1;
  if (mLine < 0) or (mLine >= Length(mLines)) then
  begin
    Exit;
  end;
  mCharacter := TLspSession.ColumnToIndex(mLines[mLine], AView.CursorPos.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  mTrigger := TAtlasSlashTrigger.TriggerChar(AKind);
  mOptions := TLspFormatOptions.Create(TAtlasEditorBuffer.BlockIndent(AView.Buffer), True);
  mView := AView;
  mKind := AKind;
  mEdits := nil;
  FSlashRequest.Start(
    procedure
    begin
      mEdits := mRunning.OnTypeFormatting(mFileName, mLine, mCharacter, mTrigger, mOptions, cSlashTimeoutMs);
    end,
    procedure(AOk: Boolean; const AError: string)
    begin
      if not AOk then
      begin
        // Beim Tippen keine Meldung; nur ins Protokoll.
        TAtlasGuard.Log('Schnellbefehl: ' + TAtlasGuard.MessageText(AError));
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.SlashCommands,
        procedure
        begin
          SlashAnswered(mView, mKind, mFileName, mText, mEdits);
        end);
    end);
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

class procedure TAtlasEditorServerCommands.SlashAnswered(const AView: IOTAEditView; AKind: TAtlasSlashKind;
  const AFileName, AText: string; const AEdits: TArray<TLspTextEdit>);
var
  mError: string;
begin
  if (Length(AEdits) = 0) or (AView = nil) or (AView.Buffer = nil) or (AView <> TAtlasEditorBuffer.ActiveView) or
    not TAtlasSlashTrigger.StillValid(AFileName, AText, AView.Buffer.FileName, TAtlasEditorBuffer.Text(AView.Buffer)) then
  begin
    Exit;
  end;
  mError := ApplyFileEdits(AFileName, AEdits, TAtlasStrings.Text(TAtlasTextId.UndoActionSlash));
  if mError <> '' then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mError]));
  end
  else if AKind = TAtlasSlashKind.DocComment then
  begin
    PlaceDocComment(AView, AText, AEdits[0]);
  end;
end;

end.
