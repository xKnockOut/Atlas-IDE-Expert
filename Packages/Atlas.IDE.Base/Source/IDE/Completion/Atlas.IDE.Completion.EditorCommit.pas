unit Atlas.IDE.Completion.EditorCommit;

// Vervollständigung im Editor (#410), Stufe Übernehmen: ein Undo-Schritt (CreateUndoableWriter) für Name,
// uses-Ergänzung und weitere Änderungen des Eintrags, Klammern (#430), Befehl des Eintrags (#473); Code-Vorlagen
// (#51) mit Einrückung der Zeile und Platzhalter-Modus (Atlas.IDE.Completion.Placeholders). Ein nicht sichtbares
// Mitglied (#2108) setzt nichts ein, sondern bietet die Aktionen seines Befehls an. Kette:
// Atlas.IDE.Completion.EditorState.

interface

uses
  ToolsAPI,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.CommitPlan,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Completion.EditorOpen;

type
  /// <summary>Code-Aktionen zur Wahl anbieten wie bei der Glühbirne; setzt die Kompositionswurzel ein.</summary>
  TAtlasOfferActionsProc = reference to procedure(const AActions: TArray<TLspCodeAction>);

  TAtlasEditorCompletionCommit = class(TAtlasEditorCompletionOpen)
  private
    FOnOfferActions: TAtlasOfferActionsProc;
    /// <summary>Stand des Editors AView fürs Übernehmen (TAtlasCommitPlan).</summary>
    function CommitContext(const AView: IOTAEditView): TAtlasCommitContext;
    /// <summary>AEdits mit einem Schreiber in den Puffer von AView.</summary>
    procedure WriteEdits(const AView: IOTAEditView; const AEdits: TAtlasCommitEdits;
      const AContext: TAtlasCommitContext);
  protected
    procedure Commit(const AItem: TAtlasCompletionItem);
    /// <summary>Setzt die Vorlage von AItem statt des Worts bis AEnd (0-basiert) ein.</summary>
    procedure CommitSnippet(const AView: IOTAEditView; const AItem: TAtlasCompletionItem; const AText,
      ALineText: string; ALine, AEnd: Integer);
    /// <summary>Befehl des Eintrags nach dem Übernehmen (#473): workspace/executeCommand; die Änderungen des
    /// Servers kommen danach über workspace/applyEdit.</summary>
    procedure RunCommand(const AItem: TAtlasCompletionItem);
    /// <summary>Nicht sichtbares Mitglied (#2108): die Code-Aktionen seines Befehls (Sichtbarkeit anheben,
    /// Eigenschaft anlegen) zur Wahl wie bei der Glühbirne; ohne Antwort die Meldung „keine Aktionen“.</summary>
    procedure OfferActions(const AItem: TAtlasCompletionItem);
    /// <summary>Die automatische ")" (#430) an ARemoveAt (Zeichen in ihrer Zeile) entfernen.</summary>
    procedure SkipAutoParen(const AView: IOTAEditView; ARemoveAt: Integer);
  private
    /// <summary>Freigabe absichern (#489): nach dem ";" der Zeile eines übernommenen Konstruktors anbieten.
    /// </summary>
    procedure WatchGuard(const AView: IOTAEditView; const AItem: TAtlasCompletionItem; const ALineText: string);
    /// <summary>Die ")" steht direkt hinter dem Cursor (#430): ihre Lage verfolgen und den Hint öffnen.</summary>
    procedure WatchAutoParen(const AView: IOTAEditView);
  public
    /// <summary>Zeigt die Aktionen für ein nicht sichtbares Mitglied (#2108); nil = Enter darauf tut nichts.
    /// </summary>
    property OnOfferActions: TAtlasOfferActionsProc read FOnOfferActions write FOnOfferActions;
    /// <summary>Setzt ASnippet am Cursor von AView ein, mit Einrückung der Zeile und Platzhaltern (#719).</summary>
    procedure InsertSnippet(const AView: IOTAEditView; const ASnippet: TAtlasSnippet);
    /// <summary>Platzhalter-Modus für schon eingesetzten Text, etwa ein ///-Gerüst (#88). ABefore: Puffertext vor
    /// dem Einsetzen (gemeinsamer Undo-Schritt), AOffset: Anfang des Texts im Puffer (Zeichen).</summary>
    procedure StartPlaceholders(const AView: IOTAEditView; const ABefore: string; AOffset: Integer;
      const AExpansion: TAtlasSnippetExpansion);
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Completion.Parentheses,
  Atlas.Core.Lsp.Client,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.Text.Lines;

const
  /// <summary>Wartezeit auf den Befehl eines Eintrags (#473); der Server antwortet, bevor er applyEdit schickt.
  /// </summary>
  cCommandTimeoutMs = 3000;

procedure WriteEdit(const AWriter: IOTAEditWriter; const AEdit: TAtlasCommitEdit);
begin
  AWriter.CopyTo(AEdit.Start);
  AWriter.DeleteTo(AEdit.Stop);
  AWriter.Insert(PAnsiChar(UTF8Encode(AEdit.Text)));
end;

{ TAtlasEditorCompletionCommit }

function TAtlasEditorCompletionCommit.CommitContext(const AView: IOTAEditView): TAtlasCommitContext;
var
  mCursor: TOTAEditPos;
  mCharacter: Integer;
begin
  Result := Default(TAtlasCommitContext);
  Result.Text := TAtlasEditorBuffer.Text(AView.Buffer);
  mCursor := AView.CursorPos;
  Result.Line := mCursor.Line;
  Result.LineText := TAtlasEditorBuffer.LineText(AView, mCursor.Line);
  mCharacter := TLspSession.ColumnToIndex(Result.LineText, mCursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer));
  // Mitten im Wort ersetzt Atlas das ganze Wort; beim Commit-Zeichen nur bis davor.
  Result.Character := TAtlasCommitPlan.WordEnd(Result.LineText, mCharacter, FCommitChar.WordEnd);
  Result.WordStart := FOpen.WordStart;
  Result.CommitWordEnd := FCommitChar.WordEnd;
  Result.CommitSuffixBytes := FCommitChar.SuffixBytes;
  Result.FixCase := TAtlasIdeSettings.Current.FixCase;
  Result.AutoParentheses := TAtlasIdeSettings.Current.AutoParentheses;
  Result.AutoUses := TAtlasIdeSettings.Current.AutoUses;
end;

procedure TAtlasEditorCompletionCommit.WriteEdits(const AView: IOTAEditView; const AEdits: TAtlasCommitEdits;
  const AContext: TAtlasCommitContext);
var
  mWriter: IOTAEditWriter;
  mEdit: TAtlasCommitEdit;
begin
  // Ein Schreiber, ein Undo-Schritt; er schreibt nur vorwärts, die Änderungen sind aufsteigend.
  mWriter := AView.Buffer.CreateUndoableWriter;
  for mEdit in AEdits do
  begin
    Log(Format('  Änderung Byte %d bis %d (Wortanfang %d, Zeile %d, Ende %d): %d Zeichen',
      [mEdit.Start, mEdit.Stop, AContext.WordStart, AContext.Line, AContext.Character, Length(mEdit.Text)]));
    WriteEdit(mWriter, mEdit);
  end;
end;

procedure TAtlasEditorCompletionCommit.Commit(const AItem: TAtlasCompletionItem);
var
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
  mCharPos: TOTACharPos;
  mContext: TAtlasCommitContext;
  mText: TAtlasCommitText;
  mEdits: TAtlasCommitEdits;
  mCursorByte: Integer;
begin
  if (FOpen.View = nil) or (FOpen.View.Buffer = nil) then
  begin
    Exit;
  end;
  mView := FOpen.View;
  mCursor := mView.CursorPos;
  mContext := CommitContext(mView);
  // Code-Vorlage (#51): eigener Weg mit Einrückung und Platzhaltern.
  if AItem.Snippet <> '' then
  begin
    CommitSnippet(mView, AItem, mContext.Text, mContext.LineText, mContext.Line, mContext.Character);
    ActiveChanged;
    Exit;
  end;
  mText := TAtlasCommitPlan.TextOf(AItem, mContext);
  mEdits := TAtlasCommitPlan.Edits(AItem, mContext, mText);
  WriteEdits(mView, mEdits, mContext);
  mCursorByte := TAtlasCommitPlan.CursorByte(mEdits, mContext, mText.CaretMarker);
  if mCursorByte >= 0 then
  begin
    mCharPos := mView.PosToCharPos(mCursorByte);
    mView.ConvertPos(False, mCursor, mCharPos);
    mView.CursorPos := mCursor;
    mView.MoveViewToCursor;
    mView.Paint;
    if mText.AutoParen then
    begin
      WatchAutoParen(mView);
    end;
  end;
  Log(Format('Übernommen: %d Zeichen (%d weitere Änderungen)', [Length(AItem.Name), Length(AItem.AdditionalEdits)]));
  WatchGuard(mView, AItem, mContext.LineText);
  RunCommand(AItem);
  ActiveChanged;
end;

procedure TAtlasEditorCompletionCommit.CommitSnippet(const AView: IOTAEditView; const AItem: TAtlasCompletionItem;
  const AText, ALineText: string; ALine, AEnd: Integer);
var
  mLineBreak: string;
  mExpansion: TAtlasSnippetExpansion;
  mPlace: TAtlasCommitSnippetPlace;
  mEdits: TAtlasCommitEdits;
  mEdit: TAtlasCommitEdit;
  mWriter: IOTAEditWriter;
  mWordStart, mSnippetChar, mShift: Integer;
begin
  // Zeilenumbrüche wie im Puffer, Einrückung wie die aktuelle Zeile.
  mLineBreak := TTextLines.LineBreakOf(AText);
  mExpansion := TAtlasSnippets.Expand(AItem.Snippet, TAtlasSnippets.IndentOf(ALineText), mLineBreak);
  // Vorlage des Servers (#51): ab dem Anfang ihres Bereichs; sonst das getippte Wort.
  mWordStart := TAtlasCommitPlan.SnippetWordStart(AItem, ALine, FOpen.WordStart);
  mSnippetChar := TAtlasEditorBuffer.CharOffset(AText, ALine - 1, mWordStart);
  mPlace.Text := AText;
  mPlace.LineBreak := mLineBreak;
  mPlace.Line := ALine;
  mPlace.WordStart := mWordStart;
  mPlace.WordEnd := AEnd;
  mEdits := TAtlasCommitPlan.SnippetEdits(AItem, mPlace, mExpansion, mShift);
  mWriter := AView.Buffer.CreateUndoableWriter;
  for mEdit in mEdits do
  begin
    WriteEdit(mWriter, mEdit);
  end;
  mWriter := nil;
  FPlaceholders.Start(AView, AText, TAtlasEditorBuffer.Text(AView.Buffer), mSnippetChar + mShift, mExpansion,
    TAtlasCommitPlan.LinkedFields(mEdits));
  RunCommand(AItem);
  Log(Format('Code-Vorlage eingesetzt: %d Platzhalter, %d weitere Änderungen',
    [Integer(Length(mExpansion.Stops)), Integer(Length(AItem.AdditionalEdits))]));
end;

procedure TAtlasEditorCompletionCommit.RunCommand(const AItem: TAtlasCompletionItem);
var
  mSession: TLspSession;
  mArguments: TJSONValue;
  mAnswer: TJSONValue;
begin
  if (AItem.Command = '') or not Assigned(FSession) then
  begin
    Exit;
  end;
  mSession := FSession();
  if (mSession = nil) or not mSession.Initialized then
  begin
    Log('Befehl des Eintrags nicht ausgeführt: keine Sitzung');
    Exit;
  end;
  mArguments := TJSONObject.ParseJSONValue(AItem.CommandArguments);
  if not (mArguments is TJSONArray) then
  begin
    mArguments.Free;
    mArguments := TJSONArray.Create;
  end;
  mAnswer := mSession.ExecuteCommand(AItem.Command, TJSONArray(mArguments), cCommandTimeoutMs);
  try
    if mAnswer = nil then
    begin
      Log('Befehl des Eintrags ohne Antwort');
    end;
  finally
    mAnswer.Free;
  end;
end;

procedure TAtlasEditorCompletionCommit.OfferActions(const AItem: TAtlasCompletionItem);
var
  mSession: TLspSession;
  mFound: TArray<TLspCodeAction>;
begin
  if (AItem.Command = '') or not Assigned(FSession) or not Assigned(FOnOfferActions) then
  begin
    Exit;
  end;
  // Ohne Sitzung, bei nicht lesbarer Datei der Deklaration oder Zeitlimit sagt die Meldung „keine Aktionen“ genug.
  mFound := nil;
  mSession := FSession();
  try
    if (mSession <> nil) and mSession.Initialized then
    begin
      mFound := mSession.CommandActions(AItem.Command, AItem.CommandArguments, cCommandTimeoutMs);
    end;
  except
    on ELspClientError do
    begin
      mFound := nil;
    end;
  end;
  if Length(mFound) = 0 then
  begin
    Log('Aktionen des Eintrags: keine (Sitzung oder Server)'); // german-ok Protokoll
  end;
  FOnOfferActions(mFound);
end;

procedure TAtlasEditorCompletionCommit.SkipAutoParen(const AView: IOTAEditView; ARemoveAt: Integer);
var
  mView: IOTAEditView;
  mLine: Integer;
begin
  mView := AView;
  mLine := FAutoParen.Line;
  if mLine = 0 then
  begin
    mLine := mView.CursorPos.Line;
  end;
  // Nicht im Benachrichtigungsaufruf selbst ändern, sondern gleich danach.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion,
    procedure
    var
      mText: string;
      mOffset: Integer;
      mWriter: IOTAEditWriter;
      mCursor: TOTAEditPos;
    begin
      mText := TAtlasEditorBuffer.Text(mView.Buffer);
      mOffset := TAtlasEditorBuffer.ByteOffset(mText, mLine - 1, ARemoveAt);
      mCursor := mView.CursorPos;
      mWriter := mView.Buffer.CreateUndoableWriter;
      mWriter.CopyTo(mOffset);
      mWriter.DeleteTo(mOffset + 1);
      mWriter := nil;
      mView.CursorPos := mCursor;
      mView.Paint;
    end);
end;

procedure TAtlasEditorCompletionCommit.WatchGuard(const AView: IOTAEditView; const AItem: TAtlasCompletionItem;
  const ALineText: string);
var
  mView: IOTAEditView;
  mGuard: TAtlasCommitGuard;
begin
  // Kam das ";" als Commit-Zeichen (#429), steht es schon da; dann gleich fragen.
  FGuard.Line := 0;
  mGuard := TAtlasCommitPlan.Guard(AItem.Kind, ALineText, FCommitChar.WordEnd);
  if mGuard = TAtlasCommitGuard.None then
  begin
    Exit;
  end;
  FGuard.Line := AView.CursorPos.Line;
  FGuard.FileName := AView.Buffer.FileName;
  if mGuard = TAtlasCommitGuard.InvokeNow then
  begin
    mView := AView;
    TAtlasMainThread.ForceQueue(TAtlasFeature.Completion,
      procedure
      begin
        if GuardPending(mView) then
        begin
          Invoke(mView, True);
        end;
      end);
  end;
end;

procedure TAtlasEditorCompletionCommit.WatchAutoParen(const AView: IOTAEditView);
var
  mLineText: string;
begin
  mLineText := TAtlasEditorBuffer.LineText(AView, AView.CursorPos.Line);
  FAutoParen := TAtlasAutoParen.Start(AView.CursorPos.Line, TLspSession.ColumnToIndex(mLineText,
    AView.CursorPos.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer)), mLineText);
  if Assigned(FOnOpenSignature) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Signature,
      procedure
      begin
        if Assigned(FOnOpenSignature) then
        begin
          FOnOpenSignature();
        end;
      end);
  end;
end;

procedure TAtlasEditorCompletionCommit.InsertSnippet(const AView: IOTAEditView; const ASnippet: TAtlasSnippet);
var
  mItem: TAtlasCompletionItem;
  mText, mLineText, mPad: string;
  mCursor: TOTAEditPos;
  mTabWidth, mCharacter: Integer;
begin
  if (AView = nil) or (AView.Buffer = nil) or (ASnippet.Body = '') then
  begin
    Exit;
  end;
  Close;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  mCursor := AView.CursorPos;
  mLineText := TAtlasEditorBuffer.LineText(AView, mCursor.Line);
  mTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  mCharacter := TLspSession.ColumnToIndex(mLineText, mCursor.Col, mTabWidth);
  // Leere Zeile mit dem Cursor hinter ihrem Ende (virtueller Platz): bis zum Cursor einrücken, damit die
  // Vorlage dort beginnt, wo der Cursor steht; die Folgezeilen bekommen dieselbe Einrückung.
  mPad := TAtlasCommitPlan.SnippetPad(mLineText, mCursor.Col, TLspSession.IndexToColumn(mLineText, Length(mLineText),
    mTabWidth));
  mItem := Default(TAtlasCompletionItem);
  mItem.Name := ASnippet.Prefix;
  mItem.Kind := TAtlasItemKind.Snippet;
  mItem.Snippet := mPad + ASnippet.Body;
  // Nichts ersetzen: Das Wort beginnt am Cursor.
  FOpen.WordStart := mCharacter;
  CommitSnippet(AView, mItem, mText, mLineText + mPad, mCursor.Line, mCharacter);
end;

procedure TAtlasEditorCompletionCommit.StartPlaceholders(const AView: IOTAEditView; const ABefore: string;
  AOffset: Integer; const AExpansion: TAtlasSnippetExpansion);
begin
  if (AView = nil) or (AView.Buffer = nil) or (FPlaceholders = nil) then
  begin
    Exit;
  end;
  Close;
  FPlaceholders.Start(AView, ABefore, TAtlasEditorBuffer.Text(AView.Buffer), AOffset, AExpansion);
end;

end.
