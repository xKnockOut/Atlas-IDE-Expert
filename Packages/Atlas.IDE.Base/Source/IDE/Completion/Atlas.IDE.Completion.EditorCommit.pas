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
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Completion.EditorOpen;

type
  /// <summary>Code-Aktionen zur Wahl anbieten wie bei der Glühbirne; setzt die Kompositionswurzel ein.</summary>
  TAtlasOfferActionsProc = reference to procedure(const AActions: TArray<TLspCodeAction>);

  TAtlasEditorCompletionCommit = class(TAtlasEditorCompletionOpen)
  private
    FOnOfferActions: TAtlasOfferActionsProc;
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
  System.Math,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Completion.Word,
  Atlas.Core.Completion.Matching,
  Atlas.Core.Completion.Parentheses,
  Atlas.Core.Completion.Placeholders,
  Atlas.Core.Lsp.Client,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.Text.Lines;

const
  /// <summary>Wartezeit auf den Befehl eines Eintrags (#473); der Server antwortet, bevor er applyEdit schickt.
  /// </summary>
  cCommandTimeoutMs = 3000;
  /// <summary>Stelle des Cursors im Einfügetext.</summary>
  cCaretMarker = '$0';

type
  TPendingEdit = record
    Start: Integer;
    Stop: Integer;
    Text: string;
    IsWord: Boolean;
    /// <summary>Stelle des entfernten "$0" in Text (ab 1) bei Zusatzänderungen (#472); 0 ohne.</summary>
    Marker: Integer;
    /// <summary>Verknüpfte Platzhalter in Text (#473), Offsets ab dem Anfang von Text.</summary>
    Stops: TArray<TAtlasSnippetStop>;
    /// <summary>Zeichenoffsets von Start und Stop im Text vor dem Einsetzen.</summary>
    CharStart: Integer;
    CharStop: Integer;
  end;

  /// <summary>Ein Übernehmen (ohne Vorlage): Text, Änderungen und Lage des Cursors danach.</summary>
  TCommitRun = record
    Owner: TAtlasEditorCompletionCommit;
    Item: TAtlasCompletionItem;
    View: IOTAEditView;
    /// <summary>Puffertext und Zeile des Cursors vor dem Übernehmen.</summary>
    Text: string;
    LineText: string;
    Cursor: TOTAEditPos;
    /// <summary>Ende des ersetzten Worts (0-basiert).</summary>
    Character: Integer;
    NewText: string;
    /// <summary>Stelle des entfernten "$0" in NewText (ab 1); 0 ohne.</summary>
    CaretMarker: Integer;
    AutoParen: Boolean;
    /// <summary>Cursor danach als Byteoffset im Puffer; -1 ohne.</summary>
    CursorByte: Integer;
    class function Create(AOwner: TAtlasEditorCompletionCommit; const AView: IOTAEditView;
      const AItem: TAtlasCompletionItem): TCommitRun; static;
    procedure PrepareText;
    function WordEdit: TPendingEdit;
    function ExtraEdit(const ATextEdit: TAtlasTextEdit): TPendingEdit;
    procedure AddEdits(AEdits: TList<TPendingEdit>);
    procedure TrackCursor(const AEdit: TPendingEdit; AShift: Integer; var ABodyByte: Integer);
    procedure Write;
    procedure PlaceCursor;
  end;

  /// <summary>Eine Code-Vorlage einsetzen (#51): Änderungen, verknüpfte Platzhalter und Verschiebung davor.
  /// </summary>
  TSnippetRun = record
    Item: TAtlasCompletionItem;
    Text: string;
    LineBreak: string;
    /// <summary>Anfang der Vorlage im Text vor dem Einsetzen (Zeichen).</summary>
    SnippetChar: Integer;
    /// <summary>Verschiebung der Vorlage durch davor liegende Zusatzänderungen (Zeichen).</summary>
    CharShift: Integer;
    Fields: TArray<TAtlasPlaceholderField>;
    function MainEdit(const AExpansion: TAtlasSnippetExpansion; ALine, AWordStart, AEnd: Integer): TPendingEdit;
    function ExtraEdit(const ATextEdit: TAtlasTextEdit): TPendingEdit;
    procedure AddEdits(AEdits: TList<TPendingEdit>; const AMain: TPendingEdit);
    procedure Write(const AView: IOTAEditView; AEdits: TList<TPendingEdit>);
  end;

function ByStart(const A, B: TPendingEdit): Integer;
begin
  Result := A.Start - B.Start;
end;

/// <summary>Byte-Länge von AText in UTF-8.</summary>
function Utf8Length(const AText: string): Integer;
begin
  Result := Length(UTF8Encode(AText));
end;

/// <summary>Schreibt AEdits aufsteigend; ein Schreiber = ein Undo-Schritt, er schreibt nur vorwärts.</summary>
procedure WriteEdit(const AWriter: IOTAEditWriter; const AEdit: TPendingEdit);
begin
  AWriter.CopyTo(AEdit.Start);
  AWriter.DeleteTo(AEdit.Stop);
  AWriter.Insert(PAnsiChar(UTF8Encode(AEdit.Text)));
end;

{ TCommitRun }

class function TCommitRun.Create(AOwner: TAtlasEditorCompletionCommit; const AView: IOTAEditView;
  const AItem: TAtlasCompletionItem): TCommitRun;
begin
  Result := Default(TCommitRun);
  Result.Owner := AOwner;
  Result.Item := AItem;
  Result.View := AView;
  Result.CursorByte := -1;
  Result.Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Result.Cursor := AView.CursorPos;
  Result.LineText := TAtlasEditorBuffer.LineText(AView, Result.Cursor.Line);
  Result.Character := TLspSession.ColumnToIndex(Result.LineText, Result.Cursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  // Über ein Commit-Zeichen: Das Wort endet davor, das Zeichen bleibt stehen.
  if AOwner.FCommitChar.WordEnd >= 0 then
  begin
    Result.Character := AOwner.FCommitChar.WordEnd;
  end
  else
  begin
    // Mitten im Wort: bis zu seinem Ende ersetzen, sonst bliebe der Rest stehen.
    Result.Character := TAtlasWord.EndAfter(Result.LineText, Result.Character);
  end;
end;

procedure TCommitRun.PrepareText;
var
  mWordStart: Integer;
  mNextChar: Char;
begin
  NewText := Item.InsertText;
  if NewText = '' then
  begin
    NewText := Item.Name;
  end;
  // Schreibweise (#433): abgeschaltet bleibt das Getippte, nur der Rest kommt dazu.
  mWordStart := Owner.FOpen.WordStart;
  if (mWordStart >= 0) and (Character >= mWordStart) then
  begin
    NewText := TAtlasCompletionMatcher.CommitText(Copy(LineText, mWordStart + 1, Character - mWordStart), NewText,
      TAtlasIdeSettings.Current.FixCase);
  end;
  if Item.HasTextEdit then
  begin
    NewText := Item.TextEdit.NewText;
  end;
  // Klammern (#430): Methode mit Parametern, nicht über ein Commit-Zeichen, keine "(" dahinter.
  mNextChar := #0;
  if Character < Length(LineText) then
  begin
    mNextChar := LineText[Character + 1];
  end;
  AutoParen := TAtlasIdeSettings.Current.AutoParentheses and (Owner.FCommitChar.WordEnd < 0) and
    (Pos(cCaretMarker, NewText) = 0) and not Item.HasTextEdit and
    TAtlasParentheses.Wanted(Item.Kind in [TAtlasItemKind.Method, TAtlasItemKind.Function_,
      TAtlasItemKind.Procedure_, TAtlasItemKind.Constructor_], Item.HasParameters, mNextChar);
  if AutoParen then
  begin
    NewText := NewText + '(' + cCaretMarker + ')';
  end;
  // "$0" im Einfügetext (XMLDoc-Tags, #435, Klammern): dort steht der Cursor danach.
  CaretMarker := Pos(cCaretMarker, NewText);
  if CaretMarker > 0 then
  begin
    Delete(NewText, CaretMarker, Length(cCaretMarker));
  end;
end;

function TCommitRun.WordEdit: TPendingEdit;
begin
  Result := Default(TPendingEdit);
  // Das getippte Wort durch den Eintrag ersetzen; mit textEdit ab dessen Anfang (Postfix-Vorlagen, #188).
  if Item.HasTextEdit then
  begin
    Result.Start := TAtlasEditorBuffer.ByteOffset(Text, Item.TextEdit.StartLine, Item.TextEdit.StartCharacter);
  end
  else
  begin
    Result.Start := TAtlasEditorBuffer.ByteOffset(Text, Cursor.Line - 1, Owner.FOpen.WordStart);
  end;
  Result.Stop := TAtlasEditorBuffer.ByteOffset(Text, Cursor.Line - 1, Character);
  // Reicht der textEdit über das Wort hinaus (Mengenklammer bis "]", #448), bis zu seinem Ende ersetzen.
  if Item.HasTextEdit then
  begin
    Result.Stop := Max(Result.Stop, TAtlasEditorBuffer.ByteOffset(Text, Item.TextEdit.EndLine,
      Item.TextEdit.EndCharacter));
  end;
  Result.Text := NewText;
  Result.IsWord := True;
end;

function TCommitRun.ExtraEdit(const ATextEdit: TAtlasTextEdit): TPendingEdit;
begin
  Result := Default(TPendingEdit);
  Result.Start := TAtlasEditorBuffer.ByteOffset(Text, ATextEdit.StartLine, ATextEdit.StartCharacter);
  Result.Stop := TAtlasEditorBuffer.ByteOffset(Text, ATextEdit.EndLine, ATextEdit.EndCharacter);
  Result.Text := ATextEdit.NewText;
  // "$0" im neuen Rumpf (#472): Dort steht der Cursor danach, sofern der Haupttext keinen hat.
  Result.Marker := Pos(cCaretMarker, Result.Text);
  if Result.Marker > 0 then
  begin
    Delete(Result.Text, Result.Marker, Length(cCaretMarker));
  end;
  if CaretMarker > 0 then
  begin
    Result.Marker := 0;
  end;
end;

procedure TCommitRun.AddEdits(AEdits: TList<TPendingEdit>);
var
  mTextEdit: TAtlasTextEdit;
begin
  AEdits.Add(WordEdit);
  // uses-Ergänzung u. ä. (#180); abschaltbar auf der Optionsseite (ARG-046). Einträge, die Code erzeugen
  // (Methode anlegen, deklarieren), brauchen ihre Zusatzänderungen immer.
  if TAtlasIdeSettings.Current.AutoUses or Item.IsAction then
  begin
    for mTextEdit in Item.AdditionalEdits do
    begin
      AEdits.Add(ExtraEdit(mTextEdit));
    end;
  end;
  AEdits.Sort(TComparer<TPendingEdit>.Construct(ByStart));
end;

procedure TCommitRun.TrackCursor(const AEdit: TPendingEdit; AShift: Integer; var ABodyByte: Integer);
begin
  if AEdit.IsWord then
  begin
    if CaretMarker > 0 then
    begin
      CursorByte := AEdit.Start + AShift + Utf8Length(Copy(AEdit.Text, 1, CaretMarker - 1));
    end
    else
    begin
      CursorByte := AEdit.Start + AShift + Utf8Length(AEdit.Text);
    end;
    if Owner.FCommitChar.WordEnd >= 0 then
    begin
      Inc(CursorByte, Owner.FCommitChar.SuffixBytes);
    end;
  end
  else if (AEdit.Marker > 0) and (ABodyByte < 0) then
  begin
    ABodyByte := AEdit.Start + AShift + Utf8Length(Copy(AEdit.Text, 1, AEdit.Marker - 1));
  end;
end;

procedure TCommitRun.Write;
var
  mEdits: TList<TPendingEdit>;
  mEdit: TPendingEdit;
  mWriter: IOTAEditWriter;
  mShift, mBodyByte: Integer;
begin
  mEdits := TList<TPendingEdit>.Create;
  try
    AddEdits(mEdits);
    mWriter := View.Buffer.CreateUndoableWriter;
    mShift := 0;
    mBodyByte := -1;
    for mEdit in mEdits do
    begin
      Owner.Log(Format('  Änderung Byte %d bis %d (Wortanfang %d, Zeile %d, Ende %d): %d Zeichen',
        [mEdit.Start, mEdit.Stop, Owner.FOpen.WordStart, Cursor.Line, Character, Length(mEdit.Text)]));
      WriteEdit(mWriter, mEdit);
      TrackCursor(mEdit, mShift, mBodyByte);
      Inc(mShift, Utf8Length(mEdit.Text) - (mEdit.Stop - mEdit.Start));
    end;
    mWriter := nil;
    if mBodyByte >= 0 then
    begin
      CursorByte := mBodyByte;
    end;
  finally
    mEdits.Free;
  end;
end;

procedure TCommitRun.PlaceCursor;
var
  mCursor: TOTAEditPos;
  mCharPos: TOTACharPos;
begin
  // Cursor hinter den übernommenen Namen.
  mCursor := Cursor;
  mCharPos := View.PosToCharPos(CursorByte);
  View.ConvertPos(False, mCursor, mCharPos);
  View.CursorPos := mCursor;
  View.MoveViewToCursor;
  View.Paint;
end;

{ TSnippetRun }

function TSnippetRun.MainEdit(const AExpansion: TAtlasSnippetExpansion; ALine, AWordStart,
  AEnd: Integer): TPendingEdit;
begin
  Result := Default(TPendingEdit);
  Result.Start := TAtlasEditorBuffer.ByteOffset(Text, ALine - 1, AWordStart);
  Result.Stop := TAtlasEditorBuffer.ByteOffset(Text, ALine - 1, AEnd);
  Result.Text := AExpansion.Text;
  Result.IsWord := True;
  Result.CharStart := SnippetChar;
  Result.CharStop := TAtlasEditorBuffer.CharOffset(Text, ALine - 1, AEnd);
  // Reicht der textEdit über das Wort hinaus (das ganze Literal, #473), bis zu seinem Ende ersetzen.
  if Item.HasTextEdit and (TAtlasEditorBuffer.ByteOffset(Text, Item.TextEdit.EndLine,
    Item.TextEdit.EndCharacter) > Result.Stop) then
  begin
    Result.Stop := TAtlasEditorBuffer.ByteOffset(Text, Item.TextEdit.EndLine, Item.TextEdit.EndCharacter);
    Result.CharStop := TAtlasEditorBuffer.CharOffset(Text, Item.TextEdit.EndLine, Item.TextEdit.EndCharacter);
  end;
end;

function TSnippetRun.ExtraEdit(const ATextEdit: TAtlasTextEdit): TPendingEdit;
var
  mLinked: TAtlasSnippetExpansion;
begin
  Result := Default(TPendingEdit);
  Result.Start := TAtlasEditorBuffer.ByteOffset(Text, ATextEdit.StartLine, ATextEdit.StartCharacter);
  Result.Stop := TAtlasEditorBuffer.ByteOffset(Text, ATextEdit.EndLine, ATextEdit.EndCharacter);
  Result.CharStart := TAtlasEditorBuffer.CharOffset(Text, ATextEdit.StartLine, ATextEdit.StartCharacter);
  Result.CharStop := TAtlasEditorBuffer.CharOffset(Text, ATextEdit.EndLine, ATextEdit.EndCharacter);
  Result.Text := ATextEdit.NewText;
  // Verknüpfte Platzhalter (#473): ohne Einrückung, Zeilenumbrüche wie im Puffer.
  if Item.LinkedEdits then
  begin
    mLinked := TAtlasSnippets.Expand(ATextEdit.NewText, '', LineBreak);
    Result.Text := mLinked.Text;
    Result.Stops := mLinked.Stops;
  end;
end;

procedure TSnippetRun.AddEdits(AEdits: TList<TPendingEdit>; const AMain: TPendingEdit);
var
  mTextEdit: TAtlasTextEdit;
  mEdit: TPendingEdit;
begin
  AEdits.Add(AMain);
  // Setter-Deklaration und -Rumpf der Vorlage „prop“ u. ä.; davor liegende verschieben den Platzhalter-Text.
  CharShift := 0;
  for mTextEdit in Item.AdditionalEdits do
  begin
    mEdit := ExtraEdit(mTextEdit);
    AEdits.Add(mEdit);
    if mEdit.Start < AMain.Start then
    begin
      Inc(CharShift, Length(mEdit.Text) - (mEdit.CharStop - mEdit.CharStart));
    end;
  end;
  AEdits.Sort(TComparer<TPendingEdit>.Construct(ByStart));
end;

procedure TSnippetRun.Write(const AView: IOTAEditView; AEdits: TList<TPendingEdit>);
var
  mWriter: IOTAEditWriter;
  mEdit: TPendingEdit;
  mStop: TAtlasSnippetStop;
  mField: TAtlasPlaceholderField;
  mShift: Integer;
begin
  // Ein Schreiber = ein Undo-Schritt für das Einsetzen; er schreibt nur vorwärts.
  mWriter := AView.Buffer.CreateUndoableWriter;
  Fields := nil;
  mShift := 0;
  for mEdit in AEdits do
  begin
    WriteEdit(mWriter, mEdit);
    // Lage der verknüpften Platzhalter im Text danach (Zeichen).
    for mStop in mEdit.Stops do
    begin
      mField.Number := mStop.Number;
      mField.Start := mEdit.CharStart + mShift + mStop.Start;
      mField.Length := mStop.Length;
      Fields := Fields + [mField];
    end;
    Inc(mShift, Length(mEdit.Text) - (mEdit.CharStop - mEdit.CharStart));
  end;
end;

{ TAtlasEditorCompletionCommit }

procedure TAtlasEditorCompletionCommit.Commit(const AItem: TAtlasCompletionItem);
var
  mRun: TCommitRun;
begin
  if (FOpen.View = nil) or (FOpen.View.Buffer = nil) then
  begin
    Exit;
  end;
  mRun := TCommitRun.Create(Self, FOpen.View, AItem);
  // Code-Vorlage (#51): eigener Weg mit Einrückung und Platzhaltern.
  if AItem.Snippet <> '' then
  begin
    CommitSnippet(mRun.View, AItem, mRun.Text, mRun.LineText, mRun.Cursor.Line, mRun.Character);
    ActiveChanged;
    Exit;
  end;
  mRun.PrepareText;
  mRun.Write;
  if mRun.CursorByte >= 0 then
  begin
    mRun.PlaceCursor;
    if mRun.AutoParen then
    begin
      WatchAutoParen(mRun.View);
    end;
  end;
  Log(Format('Übernommen: %d Zeichen (%d weitere Änderungen)', [Length(AItem.Name), Length(AItem.AdditionalEdits)]));
  WatchGuard(mRun.View, AItem, mRun.LineText);
  RunCommand(AItem);
  ActiveChanged;
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

procedure TAtlasEditorCompletionCommit.WatchGuard(const AView: IOTAEditView; const AItem: TAtlasCompletionItem;
  const ALineText: string);
var
  mView: IOTAEditView;
begin
  // Kam das ";" als Commit-Zeichen (#429), steht es schon da; dann gleich fragen.
  FGuard.Line := 0;
  if AItem.Kind <> TAtlasItemKind.Constructor_ then
  begin
    Exit;
  end;
  FGuard.Line := AView.CursorPos.Line;
  FGuard.FileName := AView.Buffer.FileName;
  if (FCommitChar.WordEnd >= 0) and (FCommitChar.WordEnd < Length(ALineText)) and
    (ALineText[FCommitChar.WordEnd + 1] = ';') then
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

procedure TAtlasEditorCompletionCommit.CommitSnippet(const AView: IOTAEditView; const AItem: TAtlasCompletionItem;
  const AText, ALineText: string; ALine, AEnd: Integer);
var
  mRun: TSnippetRun;
  mExpansion: TAtlasSnippetExpansion;
  mEdits: TList<TPendingEdit>;
  mWordStart: Integer;
begin
  mRun := Default(TSnippetRun);
  mRun.Item := AItem;
  mRun.Text := AText;
  // Zeilenumbrüche wie im Puffer, Einrückung wie die aktuelle Zeile.
  mRun.LineBreak := TTextLines.LineBreakOf(AText);
  mExpansion := TAtlasSnippets.Expand(AItem.Snippet, TAtlasSnippets.IndentOf(ALineText), mRun.LineBreak);
  // Vorlage des Servers (#51): ab dem Anfang ihres Bereichs; sonst das getippte Wort.
  mWordStart := FOpen.WordStart;
  if AItem.HasTextEdit and (AItem.TextEdit.StartLine = ALine - 1) then
  begin
    mWordStart := AItem.TextEdit.StartCharacter;
  end;
  mRun.SnippetChar := TAtlasEditorBuffer.CharOffset(AText, ALine - 1, mWordStart);
  mEdits := TList<TPendingEdit>.Create;
  try
    mRun.AddEdits(mEdits, mRun.MainEdit(mExpansion, ALine, mWordStart, AEnd));
    mRun.Write(AView, mEdits);
  finally
    mEdits.Free;
  end;
  FPlaceholders.Start(AView, AText, TAtlasEditorBuffer.Text(AView.Buffer), mRun.SnippetChar + mRun.CharShift,
    mExpansion, mRun.Fields);
  RunCommand(AItem);
  Log(Format('Code-Vorlage eingesetzt: %d Platzhalter, %d weitere Änderungen',
    [Integer(Length(mExpansion.Stops)), Integer(Length(AItem.AdditionalEdits))]));
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

procedure TAtlasEditorCompletionCommit.InsertSnippet(const AView: IOTAEditView; const ASnippet: TAtlasSnippet);
var
  mItem: TAtlasCompletionItem;
  mText, mLineText, mPad: string;
  mCursor: TOTAEditPos;
  mTabWidth, mCharacter, mEndColumn: Integer;
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
  mPad := '';
  if Trim(mLineText) = '' then
  begin
    mEndColumn := TLspSession.IndexToColumn(mLineText, Length(mLineText), mTabWidth);
    if mCursor.Col > mEndColumn then
    begin
      mPad := StringOfChar(' ', mCursor.Col - mEndColumn);
    end;
  end;
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
