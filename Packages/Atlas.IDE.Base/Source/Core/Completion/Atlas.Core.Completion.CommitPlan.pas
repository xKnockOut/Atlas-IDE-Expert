unit Atlas.Core.Completion.CommitPlan;

// Übernehmen eines Eintrags der Vervollständigung (Atlas.IDE.Completion.EditorCommit), ohne Open Tools API:
//   - Text, der eingesetzt wird: InsertText bzw. Name, Schreibweise wie getippt (FixCase), TextEdit des Servers,
//     automatische Klammern (#433) mit Schreibmarke dazwischen ($0).
//   - Änderungen im Puffer als UTF-8-Byte-Bereiche (der Schreiber der IDE zählt Bytes): das Wort, weitere
//     Änderungen (uses, Aktionen), aufsteigend nach Anfang; die Stelle der Schreibmarke danach.
//   - Code-Vorlagen: Hauptänderung, weitere Änderungen mit verknüpften Platzhaltern (#473), Verschiebung der
//     Vorlage durch Änderungen davor und die Felder der Platzhalter im Text danach.
//   - Wächter nach einem Konstruktor (#1038), Auffüllen einer leeren Zeile bis zur Schreibmarke beim Einsetzen
//     einer Vorlage.

interface

uses
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.Placeholders;

type
  /// <summary>Eine Änderung im Puffer: Start bis Stop in UTF-8-Bytes (Stand vor allen Änderungen) durch Text.
  /// </summary>
  TAtlasCommitEdit = record
    Start: Integer;
    Stop: Integer;
    Text: string;
    /// <summary>Die Änderung am Wort selbst (dort steht danach die Schreibmarke).</summary>
    IsWord: Boolean;
    /// <summary>Position (1-basiert) der Schreibmarke $0 in Text einer weiteren Änderung; 0 ohne.</summary>
    Marker: Integer;
    /// <summary>Platzhalter einer verknüpften Änderung (#473), relativ zu Text.</summary>
    Stops: TArray<TAtlasSnippetStop>;
    /// <summary>Start und Stop als Zeichenindex (nur Code-Vorlagen).</summary>
    CharStart: Integer;
    CharStop: Integer;
  end;

  TAtlasCommitEdits = TArray<TAtlasCommitEdit>;

  /// <summary>Stand des Editors beim Übernehmen.</summary>
  TAtlasCommitContext = record
    /// <summary>Ganzer Puffer.</summary>
    Text: string;
    /// <summary>Zeile des Cursors (ohne Zeilenende).</summary>
    LineText: string;
    /// <summary>Zeile des Cursors (1-basiert).</summary>
    Line: Integer;
    /// <summary>Ende des ersetzten Worts (0-basiert).</summary>
    Character: Integer;
    /// <summary>Anfang des Worts beim Öffnen (0-basiert).</summary>
    WordStart: Integer;
    /// <summary>Übernommen durch ein Commit-Zeichen: Ende des Worts davor, sonst -1.</summary>
    CommitWordEnd: Integer;
    /// <summary>UTF-8-Länge des Commit-Zeichens.</summary>
    CommitSuffixBytes: Integer;
    /// <summary>Einstellungen.</summary>
    FixCase: Boolean;
    AutoParentheses: Boolean;
    AutoUses: Boolean;
  end;

  /// <summary>Eingesetzter Text eines Eintrags.</summary>
  TAtlasCommitText = record
    Text: string;
    /// <summary>Position (1-basiert) der Schreibmarke in Text; 0 ohne.</summary>
    CaretMarker: Integer;
    /// <summary>Atlas hat „()“ angehängt (#433).</summary>
    AutoParen: Boolean;
  end;

  /// <summary>Stelle einer Code-Vorlage im Puffer.</summary>
  TAtlasCommitSnippetPlace = record
    /// <summary>Ganzer Puffer.</summary>
    Text: string;
    /// <summary>Zeilenende des Puffers.</summary>
    LineBreak: string;
    /// <summary>Zeile (1-basiert).</summary>
    Line: Integer;
    /// <summary>Anfang und Ende des ersetzten Worts (0-basiert).</summary>
    WordStart: Integer;
    WordEnd: Integer;
  end;

  /// <summary>Was nach einem Konstruktor geschieht (#1038).</summary>
  TAtlasCommitGuard = (
    /// <summary>Kein Konstruktor: nichts.</summary>
    None,
    /// <summary>Nächste Zeile beobachten.</summary>
    Watch,
    /// <summary>Mit „;“ übernommen: gleich die nächste Vervollständigung öffnen.</summary>
    InvokeNow);

  TAtlasCommitPlan = record
  public const
    /// <summary>Schreibmarke in eingesetztem Text.</summary>
    cCaretMarker = '$0';
  public
    /// <summary>Ende des ersetzten Worts: am Commit-Zeichen (ACommitWordEnd >= 0), sonst Ende des Bezeichners ab dem
    /// Cursor ACharacter.</summary>
    class function WordEnd(const ALineText: string; ACharacter, ACommitWordEnd: Integer): Integer; static;
    /// <summary>Text für AItem im Stand AContext.</summary>
    class function TextOf(const AItem: TAtlasCompletionItem; const AContext: TAtlasCommitContext):
      TAtlasCommitText; static;
    /// <summary>Änderungen fürs Übernehmen, aufsteigend nach Start.</summary>
    class function Edits(const AItem: TAtlasCompletionItem; const AContext: TAtlasCommitContext;
      const AText: TAtlasCommitText): TAtlasCommitEdits; static;
    /// <summary>Byte-Offset der Schreibmarke nach dem Schreiben von AEdits (in dieser Reihenfolge); -1 ohne
    /// Änderung am Wort.</summary>
    class function CursorByte(const AEdits: TAtlasCommitEdits; const AContext: TAtlasCommitContext;
      ACaretMarker: Integer): Integer; static;
    /// <summary>Anfang des ersetzten Worts für eine Code-Vorlage: TextEdit in der Zeile ALine (1-basiert) des
    /// Servers, sonst AWordStart.</summary>
    class function SnippetWordStart(const AItem: TAtlasCompletionItem; ALine, AWordStart: Integer): Integer; static;
    /// <summary>Änderungen einer Code-Vorlage mit ihrer Hauptänderung AExpansion an APlace; AShift liefert die
    /// Verschiebung der Vorlage (Zeichen) durch Änderungen davor.</summary>
    class function SnippetEdits(const AItem: TAtlasCompletionItem; const APlace: TAtlasCommitSnippetPlace;
      const AExpansion: TAtlasSnippetExpansion; out AShift: Integer): TAtlasCommitEdits; static;
    /// <summary>Felder der verknüpften Platzhalter im Text nach allen Änderungen.</summary>
    class function LinkedFields(const AEdits: TAtlasCommitEdits): TArray<TAtlasPlaceholderField>; static;
    /// <summary>Wächter nach dem Übernehmen von AKind mit dem Commit-Zeichen am Ende ACommitWordEnd in ALineText.
    /// </summary>
    class function Guard(AKind: TAtlasItemKind; const ALineText: string; ACommitWordEnd: Integer):
      TAtlasCommitGuard; static;
    /// <summary>Leerzeichen, um eine leere Zeile ALineText bis zur Spalte ACursorColumn aufzufüllen (Vorlage aus der
    /// Palette); AEndColumn ist die Spalte hinter dem Zeilenende.</summary>
    class function SnippetPad(const ALineText: string; ACursorColumn, AEndColumn: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Completion.Matching,
  Atlas.Core.Completion.Parentheses,
  Atlas.Core.Completion.Word,
  Atlas.Core.Lsp.TextOffsets;

/// <summary>Stabil nach Start sortieren (bei Gleichstand bleibt die Änderung am Wort vorn).</summary>
procedure SortByStart(var AEdits: TAtlasCommitEdits);
var
  mIndex, mPlace: Integer;
  mEdit: TAtlasCommitEdit;
begin
  for mIndex := 1 to High(AEdits) do
  begin
    mEdit := AEdits[mIndex];
    mPlace := mIndex - 1;
    while (mPlace >= 0) and (AEdits[mPlace].Start > mEdit.Start) do
    begin
      AEdits[mPlace + 1] := AEdits[mPlace];
      Dec(mPlace);
    end;
    AEdits[mPlace + 1] := mEdit;
  end;
end;

{ TAtlasCommitPlan }

class function TAtlasCommitPlan.WordEnd(const ALineText: string; ACharacter, ACommitWordEnd: Integer): Integer;
begin
  if ACommitWordEnd >= 0 then
  begin
    Result := ACommitWordEnd;
  end
  else
  begin
    Result := TAtlasWord.EndAfter(ALineText, ACharacter);
  end;
end;

function IsRoutine(AKind: TAtlasItemKind): Boolean;
begin
  Result := AKind in [TAtlasItemKind.Method, TAtlasItemKind.Function_, TAtlasItemKind.Procedure_,
    TAtlasItemKind.Constructor_];
end;

class function TAtlasCommitPlan.TextOf(const AItem: TAtlasCompletionItem; const AContext: TAtlasCommitContext):
  TAtlasCommitText;
var
  mNextChar: Char;
begin
  Result := Default(TAtlasCommitText);
  Result.Text := AItem.InsertText;
  if Result.Text = '' then
  begin
    Result.Text := AItem.Name;
  end;
  if (AContext.WordStart >= 0) and (AContext.Character >= AContext.WordStart) then
  begin
    Result.Text := TAtlasCompletionMatcher.CommitText(Copy(AContext.LineText, AContext.WordStart + 1,
      AContext.Character - AContext.WordStart), Result.Text, AContext.FixCase);
  end;
  if AItem.HasTextEdit then
  begin
    Result.Text := AItem.TextEdit.NewText;
  end;
  mNextChar := #0;
  if AContext.Character < Length(AContext.LineText) then
  begin
    mNextChar := AContext.LineText[AContext.Character + 1];
  end;
  // Nicht beim Übernehmen mit einem Zeichen, nicht, wenn der Text die Schreibmarke selbst setzt.
  Result.AutoParen := AContext.AutoParentheses and (AContext.CommitWordEnd < 0) and
    (Pos(cCaretMarker, Result.Text) = 0) and not AItem.HasTextEdit and
    TAtlasParentheses.Wanted(IsRoutine(AItem.Kind), AItem.HasParameters, mNextChar);
  if Result.AutoParen then
  begin
    Result.Text := Result.Text + '(' + cCaretMarker + ')';
  end;
  Result.CaretMarker := Pos(cCaretMarker, Result.Text);
  if Result.CaretMarker > 0 then
  begin
    Delete(Result.Text, Result.CaretMarker, Length(cCaretMarker));
  end;
end;

function WordEdit(const AItem: TAtlasCompletionItem; const AContext: TAtlasCommitContext; const AText: string):
  TAtlasCommitEdit;
begin
  Result := Default(TAtlasCommitEdit);
  if AItem.HasTextEdit then
  begin
    Result.Start := TAtlasTextOffsets.ByteOffset(AContext.Text, AItem.TextEdit.StartLine,
      AItem.TextEdit.StartCharacter);
  end
  else
  begin
    Result.Start := TAtlasTextOffsets.ByteOffset(AContext.Text, AContext.Line - 1, AContext.WordStart);
  end;
  Result.Stop := TAtlasTextOffsets.ByteOffset(AContext.Text, AContext.Line - 1, AContext.Character);
  if AItem.HasTextEdit then
  begin
    Result.Stop := Max(Result.Stop, TAtlasTextOffsets.ByteOffset(AContext.Text, AItem.TextEdit.EndLine,
      AItem.TextEdit.EndCharacter));
  end;
  Result.Text := AText;
  Result.IsWord := True;
end;

function ExtraEdit(const AText: string; const ATextEdit: TAtlasTextEdit; ACaretMarker: Integer): TAtlasCommitEdit;
begin
  Result := Default(TAtlasCommitEdit);
  Result.Start := TAtlasTextOffsets.ByteOffset(AText, ATextEdit.StartLine, ATextEdit.StartCharacter);
  Result.Stop := TAtlasTextOffsets.ByteOffset(AText, ATextEdit.EndLine, ATextEdit.EndCharacter);
  Result.Text := ATextEdit.NewText;
  Result.Marker := Pos(TAtlasCommitPlan.cCaretMarker, Result.Text);
  if Result.Marker > 0 then
  begin
    Delete(Result.Text, Result.Marker, Length(TAtlasCommitPlan.cCaretMarker));
  end;
  // Setzt das Wort selbst die Schreibmarke, gilt die der weiteren Änderung nicht.
  if ACaretMarker > 0 then
  begin
    Result.Marker := 0;
  end;
end;

class function TAtlasCommitPlan.Edits(const AItem: TAtlasCompletionItem; const AContext: TAtlasCommitContext;
  const AText: TAtlasCommitText): TAtlasCommitEdits;
var
  mTextEdit: TAtlasTextEdit;
begin
  Result := TArray<TAtlasCommitEdit>.Create(WordEdit(AItem, AContext, AText.Text));
  // uses-Einträge nur mit der Einstellung, Aktionen immer.
  if AContext.AutoUses or AItem.IsAction then
  begin
    for mTextEdit in AItem.AdditionalEdits do
    begin
      Result := Result + [ExtraEdit(AContext.Text, mTextEdit, AText.CaretMarker)];
    end;
  end;
  SortByStart(Result);
end;

class function TAtlasCommitPlan.CursorByte(const AEdits: TAtlasCommitEdits; const AContext: TAtlasCommitContext;
  ACaretMarker: Integer): Integer;
var
  mEdit: TAtlasCommitEdit;
  mShift, mBodyByte: Integer;
begin
  Result := -1;
  mShift := 0;
  mBodyByte := -1;
  for mEdit in AEdits do
  begin
    if mEdit.IsWord then
    begin
      if ACaretMarker > 0 then
      begin
        Result := mEdit.Start + mShift + TAtlasTextOffsets.Utf8Length(Copy(mEdit.Text, 1, ACaretMarker - 1));
      end
      else
      begin
        Result := mEdit.Start + mShift + TAtlasTextOffsets.Utf8Length(mEdit.Text);
      end;
      // Hinter das Commit-Zeichen.
      if AContext.CommitWordEnd >= 0 then
      begin
        Inc(Result, AContext.CommitSuffixBytes);
      end;
    end
    else if (mEdit.Marker > 0) and (mBodyByte < 0) then
    begin
      mBodyByte := mEdit.Start + mShift + TAtlasTextOffsets.Utf8Length(Copy(mEdit.Text, 1, mEdit.Marker - 1));
    end;
    Inc(mShift, TAtlasTextOffsets.Utf8Length(mEdit.Text) - (mEdit.Stop - mEdit.Start));
  end;
  // Schreibmarke einer weiteren Änderung (etwa im Rumpf einer erzeugten Methode) hat Vorrang.
  if mBodyByte >= 0 then
  begin
    Result := mBodyByte;
  end;
end;

class function TAtlasCommitPlan.SnippetWordStart(const AItem: TAtlasCompletionItem; ALine, AWordStart: Integer):
  Integer;
begin
  Result := AWordStart;
  if AItem.HasTextEdit and (AItem.TextEdit.StartLine = ALine - 1) then
  begin
    Result := AItem.TextEdit.StartCharacter;
  end;
end;

function SnippetMainEdit(const AItem: TAtlasCompletionItem; const APlace: TAtlasCommitSnippetPlace;
  const AExpansion: TAtlasSnippetExpansion): TAtlasCommitEdit;
var
  mEditEnd: Integer;
begin
  Result := Default(TAtlasCommitEdit);
  Result.Start := TAtlasTextOffsets.ByteOffset(APlace.Text, APlace.Line - 1, APlace.WordStart);
  Result.Stop := TAtlasTextOffsets.ByteOffset(APlace.Text, APlace.Line - 1, APlace.WordEnd);
  Result.Text := AExpansion.Text;
  Result.IsWord := True;
  Result.CharStart := TAtlasTextOffsets.CharOffset(APlace.Text, APlace.Line - 1, APlace.WordStart);
  Result.CharStop := TAtlasTextOffsets.CharOffset(APlace.Text, APlace.Line - 1, APlace.WordEnd);
  if not AItem.HasTextEdit then
  begin
    Exit;
  end;
  // Reicht der TextEdit des Servers weiter, ersetzt die Vorlage bis dorthin.
  mEditEnd := TAtlasTextOffsets.ByteOffset(APlace.Text, AItem.TextEdit.EndLine, AItem.TextEdit.EndCharacter);
  if mEditEnd > Result.Stop then
  begin
    Result.Stop := mEditEnd;
    Result.CharStop := TAtlasTextOffsets.CharOffset(APlace.Text, AItem.TextEdit.EndLine,
      AItem.TextEdit.EndCharacter);
  end;
end;

function SnippetExtraEdit(const AItem: TAtlasCompletionItem; const AText, ALineBreak: string;
  const ATextEdit: TAtlasTextEdit): TAtlasCommitEdit;
var
  mLinked: TAtlasSnippetExpansion;
begin
  Result := Default(TAtlasCommitEdit);
  Result.Start := TAtlasTextOffsets.ByteOffset(AText, ATextEdit.StartLine, ATextEdit.StartCharacter);
  Result.Stop := TAtlasTextOffsets.ByteOffset(AText, ATextEdit.EndLine, ATextEdit.EndCharacter);
  Result.CharStart := TAtlasTextOffsets.CharOffset(AText, ATextEdit.StartLine, ATextEdit.StartCharacter);
  Result.CharStop := TAtlasTextOffsets.CharOffset(AText, ATextEdit.EndLine, ATextEdit.EndCharacter);
  Result.Text := ATextEdit.NewText;
  // Verknüpfte Platzhalter (#473): die weitere Änderung ist selbst eine Vorlage.
  if AItem.LinkedEdits then
  begin
    mLinked := TAtlasSnippets.Expand(ATextEdit.NewText, '', ALineBreak);
    Result.Text := mLinked.Text;
    Result.Stops := mLinked.Stops;
  end;
end;

class function TAtlasCommitPlan.SnippetEdits(const AItem: TAtlasCompletionItem;
  const APlace: TAtlasCommitSnippetPlace; const AExpansion: TAtlasSnippetExpansion; out AShift: Integer):
  TAtlasCommitEdits;
var
  mMain, mEdit: TAtlasCommitEdit;
  mTextEdit: TAtlasTextEdit;
begin
  mMain := SnippetMainEdit(AItem, APlace, AExpansion);
  Result := TArray<TAtlasCommitEdit>.Create(mMain);
  AShift := 0;
  for mTextEdit in AItem.AdditionalEdits do
  begin
    mEdit := SnippetExtraEdit(AItem, APlace.Text, APlace.LineBreak, mTextEdit);
    Result := Result + [mEdit];
    if mEdit.Start < mMain.Start then
    begin
      Inc(AShift, Length(mEdit.Text) - (mEdit.CharStop - mEdit.CharStart));
    end;
  end;
  SortByStart(Result);
end;

class function TAtlasCommitPlan.LinkedFields(const AEdits: TAtlasCommitEdits): TArray<TAtlasPlaceholderField>;
var
  mEdit: TAtlasCommitEdit;
  mStop: TAtlasSnippetStop;
  mField: TAtlasPlaceholderField;
  mShift: Integer;
begin
  Result := nil;
  mShift := 0;
  for mEdit in AEdits do
  begin
    for mStop in mEdit.Stops do
    begin
      mField.Number := mStop.Number;
      mField.Start := mEdit.CharStart + mShift + mStop.Start;
      mField.Length := mStop.Length;
      Result := Result + [mField];
    end;
    Inc(mShift, Length(mEdit.Text) - (mEdit.CharStop - mEdit.CharStart));
  end;
end;

class function TAtlasCommitPlan.Guard(AKind: TAtlasItemKind; const ALineText: string; ACommitWordEnd: Integer):
  TAtlasCommitGuard;
begin
  if AKind <> TAtlasItemKind.Constructor_ then
  begin
    Exit(TAtlasCommitGuard.None);
  end;
  Result := TAtlasCommitGuard.Watch;
  if (ACommitWordEnd >= 0) and (ACommitWordEnd < Length(ALineText)) and (ALineText[ACommitWordEnd + 1] = ';') then
  begin
    Result := TAtlasCommitGuard.InvokeNow;
  end;
end;

class function TAtlasCommitPlan.SnippetPad(const ALineText: string; ACursorColumn, AEndColumn: Integer): string;
begin
  Result := '';
  if (Trim(ALineText) = '') and (ACursorColumn > AEndColumn) then
  begin
    Result := StringOfChar(' ', ACursorColumn - AEndColumn);
  end;
end;

end.
