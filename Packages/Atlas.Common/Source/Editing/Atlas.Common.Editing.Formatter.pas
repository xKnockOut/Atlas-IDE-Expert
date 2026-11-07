unit Atlas.Common.Editing.Formatter;

// Formatierung (#43). Die Tokenfolge bleibt immer gleich; geändert werden
// Leerraum, Zeilenumbrüche und die Schreibweise reservierter Wörter:
//   - Stellung von begin und else (Formatter.Layout, format.beginPlacement,
//     format.elsePlacement)
//   - Einrückung aus der Blockstruktur (Formatter.Indent, format.reindent),
//     sonst führende Tabs bzw. Leerzeichen in die eingestellte Art umrechnen
//   - Leerzeichen am Zeilenende entfernen
//   - genau ein Leerzeichen um := und nach Kommas
//   - reservierte Wörter klein oder groß schreiben
//   - Zuweisungen, Deklarationen und Kommentare ausrichten (format.align*)
//   - lange Zeilen umbrechen (format.maxLineLength)
//   - Zeilenende vereinheitlichen, abschließende Leerzeile
// Zeilen in mehrzeiligen Kommentaren und Strings sowie asm-Blöcke bleiben
// unverändert, ebenso Bereiche von "// atlas-format: off" bis "// atlas-format: on"
// samt dieser Zeilen (#1358; auch in { } und (* *), ohne "on" bis zum Dateiende).
// Ergebnis sind Textänderungen je Zeile bzw. Zeilenbereich.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract;

type
  TFormatter = class
  public
    /// <summary>Änderungen für die Zeilen AFirstLine bis ALastLine (-1 = bis zum Ende).
    /// Zeilenenden und die abschließende Leerzeile nur bei der ganzen Datei.</summary>
    class function Edits(const AText: string; const ATokens: TArray<TPascalToken>;
      const ASettings: TFormatStyle; AFirstLine, ALastLine: Integer): TArray<TTextEdit>; overload; static;
    /// <summary>Wie oben mit ALastLine = -1.</summary>
    class function Edits(const AText: string; const ATokens: TArray<TPascalToken>;
      const ASettings: TFormatStyle; AFirstLine: Integer): TArray<TTextEdit>; overload; static;
    /// <summary>Wie oben für die ganze Datei (AFirstLine = 0, ALastLine = -1).</summary>
    class function Edits(const AText: string; const ATokens: TArray<TPascalToken>;
      const ASettings: TFormatStyle): TArray<TTextEdit>; overload; static;
    /// <summary>Text nach dem Formatieren, z. B. für Tests und den Linter.</summary>
    class function FormatText(const AText: string; const ATokens: TArray<TPascalToken>;
      const ASettings: TFormatStyle): string; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.Formatter.Indent,
  Atlas.Common.Editing.Formatter.Layout;

type
  TLineInfo = record
    /// <summary>Zeile liegt (ab Spalte 0) in einem mehrzeiligen Token oder einem asm-Block.</summary>
    Frozen: Boolean;
    /// <summary>Ein mehrzeiliges Token beginnt hier; das Zeilenende gehört ihm.</summary>
    KeepEnd: Boolean;
  end;

  TGapEdit = record
    StartColumn: Integer;
    EndColumn: Integer;
    Text: string;
  end;

/// <summary>Breite des führenden Leerraums in Spalten (Tab bis zur nächsten Ebene).</summary>
function LeadingColumns(const ALine: string; AIndentSize: Integer; out ALength: Integer): Integer;
begin
  Result := TBlockIndenter.LeadingColumns(ALine, AIndentSize, ALength);
end;

/// <summary>Führenden Leerraum nach Spalten umrechnen (AColumn &lt; 0: vorhandene Breite), Rest unverändert.</summary>
function Reindent(const ALine: string; const ASettings: TFormatStyle; AColumn: Integer): string;
var
  mIndex, mColumns: Integer;
begin
  mColumns := LeadingColumns(ALine, ASettings.IndentSize, mIndex);
  Inc(mIndex);
  if mIndex > Length(ALine) then
  begin
    // Nur Leerraum: Zeile wird leer (falls getrimmt) oder bleibt.
    Exit(ALine);
  end;
  if AColumn >= 0 then
  begin
    mColumns := AColumn;
  end;
  Result := TBlockIndenter.IndentText(mColumns, ASettings.IndentSize, ASettings.UseTabs) + Copy(ALine, mIndex, MaxInt);
end;

procedure AddGap(AEdits: TList<TGapEdit>; AStart, AEnd: Integer; const AText: string);
var
  mEdit: TGapEdit;
begin
  mEdit.StartColumn := AStart;
  mEdit.EndColumn := AEnd;
  mEdit.Text := AText;
  AEdits.Add(mEdit);
end;

type
  /// <summary>Leerraum, Einrückung und Schreibweise je Zeile: sammelt die Änderungen innerhalb der Zeilen aus den
  /// Tokens und wendet sie samt Einrückung an.</summary>
  TLineFormatting = class
  private
    FTokens: TArray<TPascalToken>;
    FSettings: TFormatStyle;
    FInfo: TArray<TLineInfo>;
    FGaps: TArray<TList<TGapEdit>>;
    FAsmDepth: Integer;
    procedure Freeze(AFirst, ALast: Integer);
    function SkipsAsm(const AToken: TPascalToken): Boolean;
    procedure ScanToken(AIndex: Integer);
    procedure KeywordCase(const AToken: TPascalToken);
    procedure SpaceBetween(const ALeft, ARight: TPascalToken);
    procedure SymbolSpacing(AIndex: Integer);
    function IndentColumns(const ALines: TArray<TFormatLine>): TArray<Integer>;
    function FormatLine(ALine: Integer; const AText: string; AColumn: Integer): string;
  public
    constructor Create(const ATokens: TArray<TPascalToken>; const ASettings: TFormatStyle; ALineCount: Integer);
    destructor Destroy; override;
    /// <summary>Formatiert die Zeilen mit Ursprung in AFirst..ALast.</summary>
    procedure Run(var ALines: TArray<TFormatLine>; AFirst, ALast: Integer);
  end;

{ TLineFormatting }

constructor TLineFormatting.Create(const ATokens: TArray<TPascalToken>; const ASettings: TFormatStyle;
  ALineCount: Integer);
var
  mLine: Integer;
begin
  inherited Create;
  FTokens := ATokens;
  FSettings := ASettings;
  SetLength(FInfo, ALineCount);
  SetLength(FGaps, ALineCount);
  for mLine := 0 to High(FGaps) do
  begin
    FGaps[mLine] := TList<TGapEdit>.Create;
  end;
end;

destructor TLineFormatting.Destroy;
var
  mLine: Integer;
begin
  for mLine := 0 to High(FGaps) do
  begin
    FGaps[mLine].Free;
  end;
  FGaps := nil;
  inherited;
end;

procedure TLineFormatting.Freeze(AFirst, ALast: Integer);
var
  mLine: Integer;
begin
  for mLine := AFirst to Min(ALast, High(FInfo)) do
  begin
    FInfo[mLine].Frozen := True;
  end;
end;

/// <summary>asm-Blöcke: Zeilen nach "asm" bis zum end bleiben, wie sie sind. True, wenn AToken dazugehört.</summary>
function TLineFormatting.SkipsAsm(const AToken: TPascalToken): Boolean;
begin
  Result := True;
  if (AToken.Kind = TPascalTokenKind.Keyword) and AToken.IsKeyword('asm') then
  begin
    Inc(FAsmDepth);
  end
  else if (FAsmDepth > 0) and (AToken.Kind = TPascalTokenKind.Keyword) and AToken.IsKeyword('end') then
  begin
    Dec(FAsmDepth);
    Exit;
  end
  else if FAsmDepth > 0 then
  begin
    Freeze(AToken.StartPos.Line, AToken.EndPos.Line);
    Exit;
  end;
  Result := FAsmDepth > 0;
end;

procedure TLineFormatting.ScanToken(AIndex: Integer);
var
  mToken: TPascalToken;
begin
  mToken := FTokens[AIndex];
  // Mehrzeilige Tokens einfrieren; das Zeilenende ihrer ersten Zeile gehört ihnen.
  if mToken.EndPos.Line > mToken.StartPos.Line then
  begin
    FInfo[mToken.StartPos.Line].KeepEnd := True;
    Freeze(mToken.StartPos.Line + 1, mToken.EndPos.Line);
  end;
  if SkipsAsm(mToken) or FInfo[mToken.StartPos.Line].Frozen then
  begin
    Exit;
  end;
  KeywordCase(mToken);
  if mToken.Kind = TPascalTokenKind.Symbol then
  begin
    SymbolSpacing(AIndex);
  end;
end;

/// <summary>Schreibweise reservierter Wörter.</summary>
procedure TLineFormatting.KeywordCase(const AToken: TPascalToken);
var
  mWanted: string;
begin
  if (AToken.Kind <> TPascalTokenKind.Keyword) or (FSettings.KeywordCase = TKeywordCase.Preserve) then
  begin
    Exit;
  end;
  if FSettings.KeywordCase = TKeywordCase.Lower then
  begin
    mWanted := LowerCase(AToken.Text);
  end
  else
  begin
    mWanted := UpperCase(AToken.Text);
  end;
  if mWanted <> AToken.Text then
  begin
    AddGap(FGaps[AToken.StartPos.Line], AToken.StartPos.Character, AToken.EndPos.Character, mWanted);
  end;
end;

/// <summary>Genau ein Leerzeichen zwischen ALeft und ARight, wenn beide in derselben Zeile stehen.</summary>
procedure TLineFormatting.SpaceBetween(const ALeft, ARight: TPascalToken);
begin
  if (ARight.StartPos.Line = ALeft.EndPos.Line) and (ARight.StartPos.Character - ALeft.EndPos.Character <> 1) then
  begin
    AddGap(FGaps[ARight.StartPos.Line], ALeft.EndPos.Character, ARight.StartPos.Character, ' ');
  end;
end;

/// <summary>Leerzeichen um := und nach Kommas.</summary>
procedure TLineFormatting.SymbolSpacing(AIndex: Integer);
var
  mToken: TPascalToken;
begin
  mToken := FTokens[AIndex];
  if (mToken.Text = ':=') and FSettings.SpaceAroundAssignment then
  begin
    if AIndex > 0 then
    begin
      SpaceBetween(FTokens[AIndex - 1], mToken);
    end;
    if AIndex < High(FTokens) then
    begin
      SpaceBetween(mToken, FTokens[AIndex + 1]);
    end;
  end
  else if (mToken.Text = ',') and FSettings.SpaceAfterComma and (AIndex < High(FTokens)) then
  begin
    SpaceBetween(mToken, FTokens[AIndex + 1]);
  end;
end;

/// <summary>Einrückung aus der Blockstruktur (#43); nil, wenn sie nicht neu berechnet wird.</summary>
function TLineFormatting.IndentColumns(const ALines: TArray<TFormatLine>): TArray<Integer>;
var
  mLeading: TArray<Integer>;
  mLine, mWidth: Integer;
begin
  Result := nil;
  if not FSettings.Reindent then
  begin
    Exit;
  end;
  SetLength(mLeading, Length(ALines));
  for mLine := 0 to High(ALines) do
  begin
    mLeading[mLine] := LeadingColumns(ALines[mLine].Text, FSettings.IndentSize, mWidth);
  end;
  Result := TBlockIndenter.Columns(FTokens, mLeading, FSettings.IndentSize);
end;

function TLineFormatting.FormatLine(ALine: Integer; const AText: string; AColumn: Integer): string;
var
  mGap: TGapEdit;
begin
  Result := AText;
  // Von rechts nach links, damit die Spalten gültig bleiben.
  FGaps[ALine].Sort(TComparer<TGapEdit>.Construct(
    function(const A, B: TGapEdit): Integer
    begin
      Result := B.StartColumn - A.StartColumn;
    end));
  for mGap in FGaps[ALine] do
  begin
    Result := Copy(Result, 1, mGap.StartColumn) + mGap.Text + Copy(Result, mGap.EndColumn + 1, MaxInt);
  end;
  Result := Reindent(Result, FSettings, AColumn);
  if FSettings.TrimTrailingWhitespace and not FInfo[ALine].KeepEnd then
  begin
    Result := TrimRight(Result);
  end;
end;

procedure TLineFormatting.Run(var ALines: TArray<TFormatLine>; AFirst, ALast: Integer);
var
  mColumns: TArray<Integer>;
  mIndex, mLine, mColumn: Integer;
begin
  for mIndex := 0 to High(FTokens) do
  begin
    if FTokens[mIndex].StartPos.Line > High(FInfo) then
    begin
      Break;
    end;
    ScanToken(mIndex);
  end;
  mColumns := IndentColumns(ALines);
  for mLine := 0 to High(ALines) do
  begin
    if FInfo[mLine].Frozen or (ALines[mLine].Origin < AFirst) or (ALines[mLine].Origin > ALast) then
    begin
      Continue;
    end;
    mColumn := -1;
    if mColumns <> nil then
    begin
      mColumn := mColumns[mLine];
    end;
    ALines[mLine].Text := FormatLine(mLine, ALines[mLine].Text, mColumn);
  end;
end;

/// <summary>Leerraum, Einrückung und Schreibweise je Zeile (Zeilen mit Ursprung in AFirst..ALast).</summary>
procedure FormatLines(var ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
  const ASettings: TFormatStyle; AFirst, ALast: Integer);
var
  mFormatting: TLineFormatting;
begin
  mFormatting := TLineFormatting.Create(ATokens, ASettings, Length(ALines));
  try
    mFormatting.Run(ALines, AFirst, ALast);
  finally
    mFormatting.Free;
  end;
end;

function JoinTexts(const ALines: TArray<TFormatLine>; const ALineBreak: string): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 0 to High(ALines) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(ALineBreak);
      end;
      mBuilder.Append(ALines[mIndex].Text);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>"atlas-format: off" bzw. "on" in einem Kommentar (#1358); Leerzeichen und Groß-/Kleinschreibung zählen
/// nicht. AOff gibt an, welche Marke es ist.</summary>
function IsFormatMarker(const AToken: TPascalToken; out AOff: Boolean): Boolean;
var
  mText: string;
begin
  Result := False;
  AOff := False;
  if AToken.Kind <> TPascalTokenKind.Comment then
  begin
    Exit;
  end;
  mText := AToken.Text;
  if mText.StartsWith('//') then
  begin
    mText := Copy(mText, 3, MaxInt);
  end
  else if mText.StartsWith('(*') then
  begin
    mText := Copy(mText, 3, Length(mText) - 4);
  end
  else if mText.StartsWith('{') then
  begin
    mText := Copy(mText, 2, Length(mText) - 2);
  end;
  mText := LowerCase(StringReplace(mText, ' ', '', [rfReplaceAll])).Trim;
  if mText = 'atlas-format:off' then
  begin
    AOff := True;
    Result := True;
  end
  else
  begin
    Result := mText = 'atlas-format:on';
  end;
end;

/// <summary>Zeilen von ALineCount, die zwischen den Marken liegen (#1358), samt der Zeilen der Marken.</summary>
function ProtectedLines(const ATokens: TArray<TPascalToken>; ALineCount: Integer): TArray<Boolean>;
var
  mToken: TPascalToken;
  mIsOff: Boolean;
  mOffLine, mLine: Integer;
begin
  SetLength(Result, ALineCount);
  mOffLine := -1;
  for mToken in ATokens do
  begin
    if not IsFormatMarker(mToken, mIsOff) then
    begin
      Continue;
    end;
    if mIsOff and (mOffLine < 0) then
    begin
      mOffLine := mToken.StartPos.Line;
    end
    else if not mIsOff and (mOffLine >= 0) then
    begin
      for mLine := mOffLine to Min(mToken.EndPos.Line, ALineCount - 1) do
      begin
        Result[mLine] := True;
      end;
      mOffLine := -1;
    end;
  end;
  if mOffLine >= 0 then
  begin
    for mLine := mOffLine to ALineCount - 1 do
    begin
      Result[mLine] := True;
    end;
  end;
end;

/// <summary>Mindestens ein Eintrag von AFlags in AFrom..ATo ist gesetzt.</summary>
function AnySet(const AFlags: TArray<Boolean>; AFrom, ATo: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := AFrom to ATo do
  begin
    Result := Result or AFlags[mIndex];
  end;
end;

type
  /// <summary>Ein Formatierlauf über alle Schritte: Ursprungszeilen, Ergebniszeilen mit Ursprung und die an die
  /// vorige gehängten Ursprungszeilen.</summary>
  TFormatRun = class
  private
    FSettings: TFormatStyle;
    FLineBreak: string;
    FOriginal: TArray<string>;
    FJoined: TArray<Boolean>;
    FLines: TArray<TFormatLine>;
    FFirst: Integer;
    FLast: Integer;
    FWholeFile: Boolean;
    function Tokenized: TArray<TPascalToken>;
    function Aligns(AKind: TFormatAlignment): Boolean;
    procedure AlignAll;
    procedure WrapLong;
    function GroupEnd(ALine: Integer): Integer;
    procedure KeepOriginal(AKept: TList<TFormatLine>; ALine, AStop: Integer; var AIndex: Integer);
    procedure TakeFormatted(AKept: TList<TFormatLine>; AStop: Integer; var AIndex: Integer);
    procedure KeepProtected(const AProtected: TArray<Boolean>);
    function GroupText(AStop: Integer; var AIndex: Integer): string;
    function ChangesLineBreaks: Boolean;
    function FileEdit: TTextEdit;
    function LineEdits: TArray<TTextEdit>;
  public
    constructor Create(const AText: string; const ASettings: TFormatStyle; AFirstLine, ALastLine: Integer);
    /// <summary>Alle Schritte über die Tokens des ursprünglichen Texts.</summary>
    procedure Run(const ATokens: TArray<TPascalToken>);
    /// <summary>Änderungen je Ursprungszeile samt angehängter Folgezeilen.</summary>
    function Edits: TArray<TTextEdit>;
    /// <summary>Text nach dem Formatieren.</summary>
    function Text: string;
  end;

{ TFormatRun }

constructor TFormatRun.Create(const AText: string; const ASettings: TFormatStyle; AFirstLine, ALastLine: Integer);
begin
  inherited Create;
  FSettings := ASettings;
  if FSettings.IndentSize < 1 then
  begin
    FSettings.IndentSize := 2;
  end;
  FLineBreak := TTextLines.LineBreakOf(AText);
  FOriginal := TTextLines.SplitLines(AText);
  FWholeFile := (AFirstLine <= 0) and (ALastLine < 0);
  FFirst := Max(AFirstLine, 0);
  FLast := High(FOriginal);
  if ALastLine >= 0 then
  begin
    FLast := Min(ALastLine, High(FOriginal));
  end;
end;

function TFormatRun.Tokenized: TArray<TPascalToken>;
begin
  Result := TPascalLexer.Tokenize(JoinTexts(FLines, FLineBreak));
end;

function TFormatRun.Aligns(AKind: TFormatAlignment): Boolean;
begin
  Result := False;
  case AKind of
    TFormatAlignment.Assignments:
      Result := FSettings.AlignAssignments;
    TFormatAlignment.Declarations, TFormatAlignment.Constants:
      Result := FSettings.AlignDeclarations;
    TFormatAlignment.Comments:
      Result := FSettings.AlignComments;
  end;
end;

procedure TFormatRun.AlignAll;
var
  mKind: TFormatAlignment;
begin
  for mKind := Low(TFormatAlignment) to High(TFormatAlignment) do
  begin
    if Aligns(mKind) then
    begin
      TFormatLayout.Align(FLines, Tokenized, mKind, FFirst, FLast);
    end;
  end;
end;

procedure TFormatRun.WrapLong;
var
  mRound: Integer;
begin
  if FSettings.MaxLineLength <= 0 then
  begin
    Exit;
  end;
  for mRound := 1 to 64 do
  begin
    if not TFormatLayout.Wrap(FLines, Tokenized, FSettings, FFirst, FLast) then
    begin
      Break;
    end;
  end;
end;

procedure TFormatRun.Run(const ATokens: TArray<TPascalToken>);
var
  mTokens: TArray<TPascalToken>;
begin
  FLines := TFormatLayout.Place(FOriginal, ATokens, FSettings, FFirst, FLast, FJoined);
  if Length(FLines) = Length(FOriginal) then
  begin
    mTokens := ATokens;
  end
  else
  begin
    mTokens := Tokenized;
  end;
  FormatLines(FLines, mTokens, FSettings, FFirst, FLast);
  AlignAll;
  WrapLong;
  KeepProtected(ProtectedLines(ATokens, Length(FOriginal)));
end;

/// <summary>Letzte Ursprungszeile der Gruppe ab ALine: ALine und die an sie gehängten Folgezeilen.</summary>
function TFormatRun.GroupEnd(ALine: Integer): Integer;
begin
  Result := ALine;
  while (Result < High(FOriginal)) and FJoined[Result + 1] do
  begin
    Inc(Result);
  end;
end;

/// <summary>Übernimmt die Ursprungszeilen ALine..AStop unverändert und überspringt ihre Ergebniszeilen.</summary>
procedure TFormatRun.KeepOriginal(AKept: TList<TFormatLine>; ALine, AStop: Integer; var AIndex: Integer);
var
  mLine: Integer;
  mItem: TFormatLine;
begin
  while (AIndex <= High(FLines)) and (FLines[AIndex].Origin <= AStop) do
  begin
    Inc(AIndex);
  end;
  for mLine := ALine to AStop do
  begin
    mItem.Text := FOriginal[mLine];
    mItem.Origin := mLine;
    AKept.Add(mItem);
    FJoined[mLine] := False;
  end;
end;

/// <summary>Übernimmt die Ergebniszeilen ab AIndex mit Ursprung bis AStop.</summary>
procedure TFormatRun.TakeFormatted(AKept: TList<TFormatLine>; AStop: Integer; var AIndex: Integer);
begin
  while (AIndex <= High(FLines)) and (FLines[AIndex].Origin <= AStop) do
  begin
    AKept.Add(FLines[AIndex]);
    Inc(AIndex);
  end;
end;

/// <summary>Geschützte Zeilen (#1358) wie im Original: Jede Gruppe aus einer Ursprungszeile und den an sie
/// gehängten Folgezeilen, die eine geschützte Zeile enthält, kommt unverändert zurück.</summary>
procedure TFormatRun.KeepProtected(const AProtected: TArray<Boolean>);
var
  mKept: TList<TFormatLine>;
  mLine, mStop, mIndex: Integer;
begin
  if not AnySet(AProtected, 0, High(AProtected)) then
  begin
    Exit;
  end;
  mKept := TList<TFormatLine>.Create;
  try
    mIndex := 0;
    mLine := 0;
    while mLine <= High(FOriginal) do
    begin
      mStop := GroupEnd(mLine);
      if AnySet(AProtected, mLine, mStop) then
      begin
        KeepOriginal(mKept, mLine, mStop, mIndex);
      end
      else
      begin
        TakeFormatted(mKept, mStop, mIndex);
      end;
      mLine := mStop + 1;
    end;
    TakeFormatted(mKept, MaxInt, mIndex);
    FLines := mKept.ToArray;
  finally
    mKept.Free;
  end;
end;

/// <summary>Ergebniszeilen ab AIndex mit Ursprung bis AStop, durch Zeilenenden getrennt.</summary>
function TFormatRun.GroupText(AStop: Integer; var AIndex: Integer): string;
var
  mFirstPart: Boolean;
begin
  Result := '';
  mFirstPart := True;
  while (AIndex <= High(FLines)) and (FLines[AIndex].Origin <= AStop) do
  begin
    if not mFirstPart then
    begin
      Result := Result + FLineBreak;
    end;
    mFirstPart := False;
    Result := Result + FLines[AIndex].Text;
    Inc(AIndex);
  end;
end;

/// <summary>Die ganze Datei bekommt andere Zeilenenden.</summary>
function TFormatRun.ChangesLineBreaks: Boolean;
begin
  Result := FWholeFile and (FSettings.EndOfLine <> '') and (FSettings.EndOfLine <> FLineBreak) and
    (Length(FOriginal) > 1);
end;

/// <summary>Neue Zeilenenden: die ganze Datei auf einmal ersetzen.</summary>
function TFormatRun.FileEdit: TTextEdit;
var
  mText: string;
begin
  mText := JoinTexts(FLines, FSettings.EndOfLine);
  if FSettings.InsertFinalNewline and (mText <> '') and not mText.EndsWith(FSettings.EndOfLine) then
  begin
    mText := mText + FSettings.EndOfLine;
  end;
  Result := TTextEdit.Create(TTextRange.Create(0, 0, High(FOriginal), Length(FOriginal[High(FOriginal)])), mText);
end;

/// <summary>Je Ursprungszeile (samt angehängter Folgezeilen) eine Änderung.</summary>
function TFormatRun.LineEdits: TArray<TTextEdit>;
var
  mFound: TList<TTextEdit>;
  mLine, mIndex, mStop: Integer;
  mText: string;
begin
  mFound := TList<TTextEdit>.Create;
  try
    mIndex := 0;
    for mLine := 0 to High(FOriginal) do
    begin
      if FJoined[mLine] then
      begin
        Continue;
      end;
      mStop := GroupEnd(mLine);
      mText := GroupText(mStop, mIndex);
      if (mStop > mLine) or (mText <> FOriginal[mLine]) then
      begin
        mFound.Add(TTextEdit.Create(TTextRange.Create(mLine, 0, mStop, Length(FOriginal[mStop])), mText));
      end;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

function TFormatRun.Edits: TArray<TTextEdit>;
var
  mEnd: Integer;
begin
  if ChangesLineBreaks then
  begin
    Result := [FileEdit];
    Exit;
  end;
  Result := LineEdits;
  if FWholeFile and FSettings.InsertFinalNewline and (FLines <> nil) and (FLines[High(FLines)].Text <> '') then
  begin
    mEnd := Length(FOriginal[High(FOriginal)]);
    Result := Result + [TTextEdit.Create(TTextRange.Create(High(FOriginal), mEnd, High(FOriginal), mEnd),
      FLineBreak)];
  end;
end;

function TFormatRun.Text: string;
var
  mLineBreak: string;
begin
  mLineBreak := FLineBreak;
  if (FSettings.EndOfLine <> '') and (Length(FOriginal) > 1) then
  begin
    mLineBreak := FSettings.EndOfLine;
  end;
  Result := JoinTexts(FLines, mLineBreak);
  if FSettings.InsertFinalNewline and (FLines <> nil) and (FLines[High(FLines)].Text <> '') then
  begin
    Result := Result + mLineBreak;
  end;
end;

{ TFormatter }

class function TFormatter.Edits(const AText: string; const ATokens: TArray<TPascalToken>;
  const ASettings: TFormatStyle; AFirstLine: Integer): TArray<TTextEdit>;
begin
  Result := Edits(AText, ATokens, ASettings, AFirstLine, -1);
end;

class function TFormatter.Edits(const AText: string; const ATokens: TArray<TPascalToken>;
  const ASettings: TFormatStyle): TArray<TTextEdit>;
begin
  Result := Edits(AText, ATokens, ASettings, 0, -1);
end;

class function TFormatter.Edits(const AText: string; const ATokens: TArray<TPascalToken>;
  const ASettings: TFormatStyle; AFirstLine, ALastLine: Integer): TArray<TTextEdit>;
var
  mRun: TFormatRun;
begin
  mRun := TFormatRun.Create(AText, ASettings, AFirstLine, ALastLine);
  try
    mRun.Run(ATokens);
    Result := mRun.Edits;
  finally
    mRun.Free;
  end;
end;

class function TFormatter.FormatText(const AText: string; const ATokens: TArray<TPascalToken>;
  const ASettings: TFormatStyle): string;
var
  mRun: TFormatRun;
begin
  mRun := TFormatRun.Create(AText, ASettings, 0, -1);
  try
    mRun.Run(ATokens);
    Result := mRun.Text;
  finally
    mRun.Free;
  end;
end;

end.
