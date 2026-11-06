unit Atlas.Common.Editing.SmartIndent;

// Einrückung beim Tippen (#1827), ohne Protokollbezug. Die IDE hat den
// Zeilenumbruch schon eingefügt; AfterEnter bekommt den Text danach und die
// neue Zeile und sagt, was sich an ihr und an der Zeile darüber ändert:
// - Neue Zeile (#1828): Spalte, die der Formatierer (TBlockIndenter, #43) dort
//   einer Anweisung gäbe, also eine Ebene tiefer hinter then, else, do, begin,
//   try, repeat, case-Marken und Abschnitten, nach der einzelnen Anweisung
//   zurück. Steht die Zeile in einer offenen Klammer, unter dem ersten
//   Argument; setzt sie eine Anweisung ohne Klammer fort, eine Ebene tiefer
//   als deren erste Zeile.
// - Schlusswort davor (#1829): Beginnt die Zeile darüber mit end, until,
//   finally, except oder else, kommt sie auf die Spalte ihres Gegenstücks.
// - String getrennt (#1831): Endet die Zeile darüber in einem offenen String,
//   wird er dort mit "' +" geschlossen und die neue Zeile beginnt mit "'",
//   eine Ebene tiefer als die Anweisung (Indent) bzw. ausgerichtet wie in
//   einer offenen Klammer, sonst unter dem ersten Wert hinter := (Align).
// Die Spalten folgen der vorhandenen Einrückung: Weicht die Datei vom Stil ab,
// verschiebt die nächste Codezeile darüber das Ergebnis um ihren Abstand.
// In Kommentaren und mehrzeiligen Strings tut AfterEnter nichts (dort setzt
// das Plugin Kommentare fort, #696).

interface

uses
  Atlas.Common.Documents.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Einrückung der Zeile hinter einem getrennten String (#1831).</summary>
  TStringContinuation = (Indent, Align);
{$SCOPEDENUMS OFF}

  TSmartIndentOptions = record
    /// <summary>Neue Zeile nach der Blockstruktur einrücken (smartIndent.afterEnter).</summary>
    AfterEnter: Boolean;
    /// <summary>Schlusswort in der Zeile darüber zurückrücken (smartIndent.outdentClosers).</summary>
    OutdentClosers: Boolean;
    /// <summary>String beim Umbruch schließen und verbinden (smartIndent.splitStrings).</summary>
    SplitStrings: Boolean;
    StringContinuation: TStringContinuation;
    /// <summary>Breite einer Ebene in Spalten.</summary>
    IndentSize: Integer;
    /// <summary>Neue Einrückung mit Tabulatoren je Ebene.</summary>
    UseTabs: Boolean;
    /// <summary>Alles an, Fortsetzung eingerückt, Ebene 2, Leerzeichen.</summary>
    class function Default: TSmartIndentOptions; static;
  end;

  TSmartIndentResult = record
    /// <summary>Änderungen an der neuen Zeile und an der darüber; leer, wenn alles schon stimmt.</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Schreibmarke nach den Änderungen.</summary>
    Cursor: TTextPosition;
  end;

  TSmartIndent = class
  public
    /// <summary>Nach Enter: ALine ist die neue Zeile (0-basiert), vor der Schreibmarke steht nur Leerraum.
    /// False, wenn Atlas dort nichts bestimmt (Kommentar, mehrzeiliger String, asm, alles aus).</summary>
    class function AfterEnter(const AText: string; ALine: Integer; const AOptions: TSmartIndentOptions;
      out AResult: TSmartIndentResult): Boolean; static;
    /// <summary>Spalte, die eine Anweisung am Anfang der Zeile ALine bekäme (Einfügen, #1832); False wie oben.
    /// </summary>
    class function ColumnAt(const AText: string; ALine, AIndentSize: Integer; out AColumn: Integer): Boolean;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.Formatter.Indent;

const
  /// <summary>Steht für die Rechnung in einer leeren neuen Zeile.</summary>
  cPlaceholder = 'AtlasCursor';
  cClosers: array[0..4] of string = ('end', 'until', 'finally', 'except', 'else');

type
  /// <summary>Text, Tokens und Spalten einer Rechnung.</summary>
  TIndentScan = class
  private
    FLines: TArray<string>;
    FTokens: TArray<TPascalToken>;
    FColumns: TArray<Integer>;
    FInfo: TArray<TIndentLineInfo>;
    FStep: Integer;
    /// <summary>Erstes bzw. letztes Token je Zeile; -1 ohne.</summary>
    FFirst: TArray<Integer>;
    FLast: TArray<Integer>;
    procedure IndexLines;
    function IsCode(AIndex: Integer): Boolean;
    function OpenBracket(ALine: Integer): Integer;
  public
    /// <summary>ALine bekommt den Platzhalter, wenn sie ohne Code ist.</summary>
    constructor Create(const AText: string; ALine, AIndentSize: Integer);
    /// <summary>Ein Token beginnt über ALine und reicht hinein (Kommentar, mehrzeiliger String).</summary>
    function InsideToken(ALine: Integer): Boolean;
    /// <summary>Spalte des Zeichens ACharacter (0-basiert) der Zeile ALine, Tabulatoren bis zur nächsten Ebene.
    /// </summary>
    function VisualColumn(ALine, ACharacter: Integer): Integer;
    /// <summary>Vorhandene Einrückung minus Zielspalte der nächsten gesetzten Codezeile ab ALine aufwärts.</summary>
    function Shift(ALine: Integer): Integer;
    /// <summary>Spalte für die Zeile ALine nach der Blockstruktur; False, wenn sie bleibt.</summary>
    function TargetColumn(ALine: Integer; out AColumn: Integer): Boolean;
    /// <summary>Spalte für die Zeile ALine in einer offenen Klammer: unter dem ersten Argument, vor der
    /// schließenden Klammer wie die Zeile der öffnenden; False außerhalb einer Klammer.</summary>
    function BracketColumn(ALine: Integer; out AColumn: Integer): Boolean;
    /// <summary>Spalte einer Fortsetzungszeile ALine: in offener Klammer ausgerichtet, sonst eine Ebene tiefer als
    /// die Anweisung bzw. wie die Zeile darüber.</summary>
    function ContinuationColumn(ALine: Integer): Integer;
    /// <summary>Spalte unter dem ersten Wert der Anweisung, zu der ALine gehört (hinter := bzw. ihr erster
    /// String); False ohne.</summary>
    function ValueColumn(ALine: Integer; out AColumn: Integer): Boolean;
    /// <summary>Erstes Codewort der Zeile ist ein Schlusswort.</summary>
    function StartsWithCloser(ALine: Integer): Boolean;
    /// <summary>Letztes Token der Zeile ist ein offener einzeiliger String mit Inhalt.</summary>
    function EndsInOpenString(ALine: Integer): Boolean;
    property Lines: TArray<string> read FLines;
    property Tokens: TArray<TPascalToken> read FTokens;
    property Columns: TArray<Integer> read FColumns;
    property Info: TArray<TIndentLineInfo> read FInfo;
    property Step: Integer read FStep;
    property LastToken: TArray<Integer> read FLast;
  end;

  /// <summary>Eine Rechnung von AfterEnter.</summary>
  TEnterRun = class
  private
    FScan: TIndentScan;
    FLine: Integer;
    FOptions: TSmartIndentOptions;
    FResult: TSmartIndentResult;
    function IndentText(AColumn: Integer): string;
    procedure SetIndent(ALine, AColumn: Integer; const ASuffix: string);
    function SplitString: Boolean;
    function CloserColumn(out AColumn: Integer): Boolean;
    function NewLineColumn(ACloser: Boolean; ACloserColumn: Integer; out AColumn: Integer): Boolean;
    function Reindent: Boolean;
  public
    constructor Create(const AText: string; ALine: Integer; const AOptions: TSmartIndentOptions);
    destructor Destroy; override;
    function Run(out AResult: TSmartIndentResult): Boolean;
  end;

{ TSmartIndentOptions }

class function TSmartIndentOptions.Default: TSmartIndentOptions;
begin
  Result.AfterEnter := True;
  Result.OutdentClosers := True;
  Result.SplitStrings := True;
  Result.StringContinuation := TStringContinuation.Indent;
  Result.IndentSize := 2;
  Result.UseTabs := False;
end;

{ TIndentScan }

constructor TIndentScan.Create(const AText: string; ALine, AIndentSize: Integer);
var
  mLength, mLine: Integer;
begin
  inherited Create;
  FStep := Max(AIndentSize, 1);
  FLines := TTextLines.SplitLines(AText);
  SetLength(FColumns, Length(FLines));
  for mLine := 0 to High(FLines) do
  begin
    FColumns[mLine] := TBlockIndenter.LeadingColumns(FLines[mLine], FStep, mLength);
  end;
  // Leere Zeile: Der Platzhalter zeigt dem Formatierer, wo die nächste Anweisung beginnt.
  if (ALine >= 0) and (ALine <= High(FLines)) and (Trim(FLines[ALine]) = '') then
  begin
    FLines[ALine] := FLines[ALine] + cPlaceholder;
  end;
  FTokens := TPascalLexer.Tokenize(TTextLines.JoinLines(FLines, #10));
  IndexLines;
  FInfo := TBlockIndenter.Lines(FTokens, FColumns, FStep);
end;

procedure TIndentScan.IndexLines;
var
  mIndex, mLine: Integer;
begin
  SetLength(FFirst, Length(FLines));
  SetLength(FLast, Length(FLines));
  for mLine := 0 to High(FLines) do
  begin
    FFirst[mLine] := -1;
    FLast[mLine] := -1;
  end;
  for mIndex := 0 to High(FTokens) do
  begin
    mLine := FTokens[mIndex].StartPos.Line;
    if mLine > High(FLines) then
    begin
      Break;
    end;
    if FFirst[mLine] < 0 then
    begin
      FFirst[mLine] := mIndex;
    end;
    FLast[FTokens[mIndex].EndPos.Line] := mIndex;
  end;
end;

function TIndentScan.IsCode(AIndex: Integer): Boolean;
begin
  Result := not (FTokens[AIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

function TIndentScan.InsideToken(ALine: Integer): Boolean;
var
  mToken: TPascalToken;
begin
  Result := False;
  for mToken in FTokens do
  begin
    if mToken.StartPos.Line >= ALine then
    begin
      Exit;
    end;
    if mToken.EndPos.Line >= ALine then
    begin
      Exit(True);
    end;
  end;
end;

function TIndentScan.VisualColumn(ALine, ACharacter: Integer): Integer;
var
  mIndex: Integer;
  mText: string;
begin
  mText := FLines[ALine];
  Result := 0;
  for mIndex := 1 to Min(ACharacter, Length(mText)) do
  begin
    if mText[mIndex] = #9 then
    begin
      Result := (Result div FStep + 1) * FStep;
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

function TIndentScan.Shift(ALine: Integer): Integer;
var
  mLine: Integer;
begin
  mLine := ALine;
  while mLine >= 0 do
  begin
    if (FFirst[mLine] >= 0) and IsCode(FFirst[mLine]) and FInfo[mLine].Placed then
    begin
      Exit(FColumns[mLine] - FInfo[mLine].Column);
    end;
    Dec(mLine);
  end;
  Result := 0;
end;

function TIndentScan.TargetColumn(ALine: Integer; out AColumn: Integer): Boolean;
begin
  AColumn := FColumns[ALine];
  Result := FInfo[ALine].Placed;
  if not Result then
  begin
    Exit;
  end;
  if FInfo[ALine].Continued then
  begin
    AColumn := ContinuationColumn(ALine);
  end
  else
  begin
    AColumn := Max(FInfo[ALine].Column + Shift(ALine - 1), 0);
  end;
end;

/// <summary>Innerste Klammer, die die Anweisung der Zeile ALine vor deren erstem Token offen hat; -1 ohne.
/// </summary>
function TIndentScan.OpenBracket(ALine: Integer): Integer;
var
  mStack: TArray<Integer>;
  mIndex: Integer;
begin
  mStack := nil;
  mIndex := Max(FFirst[FInfo[ALine].StatementLine], 0);
  while (mIndex <= High(FTokens)) and (FTokens[mIndex].StartPos.Line < ALine) do
  begin
    if FTokens[mIndex].IsSymbol('(') or FTokens[mIndex].IsSymbol('[') then
    begin
      mStack := mStack + [mIndex];
    end
    else if (FTokens[mIndex].IsSymbol(')') or FTokens[mIndex].IsSymbol(']')) and (Length(mStack) > 0) then
    begin
      SetLength(mStack, Length(mStack) - 1);
    end;
    Inc(mIndex);
  end;
  Result := -1;
  if Length(mStack) > 0 then
  begin
    Result := mStack[High(mStack)];
  end;
end;

function TIndentScan.BracketColumn(ALine: Integer; out AColumn: Integer): Boolean;
var
  mOpen, mNext: Integer;
  mFirst: TPascalToken;
begin
  Result := FFirst[ALine] >= 0;
  if not Result then
  begin
    Exit;
  end;
  mOpen := OpenBracket(ALine);
  Result := mOpen >= 0;
  if not Result then
  begin
    Exit;
  end;
  mFirst := FTokens[FFirst[ALine]];
  if mFirst.IsSymbol(')') or mFirst.IsSymbol(']') then
  begin
    AColumn := FColumns[FTokens[mOpen].StartPos.Line];
    Exit;
  end;
  mNext := mOpen + 1;
  if (mNext < FFirst[ALine]) and (FTokens[mNext].StartPos.Line = FTokens[mOpen].StartPos.Line) then
  begin
    AColumn := VisualColumn(FTokens[mNext].StartPos.Line, FTokens[mNext].StartPos.Character);
  end
  else
  begin
    AColumn := FColumns[FTokens[mOpen].StartPos.Line] + FStep;
  end;
end;

function TIndentScan.ContinuationColumn(ALine: Integer): Integer;
begin
  if BracketColumn(ALine, Result) then
  begin
    Exit;
  end;
  Result := FColumns[ALine - 1];
  if FInfo[ALine].StatementLine = ALine - 1 then
  begin
    Inc(Result, FStep);
  end;
end;

function TIndentScan.ValueColumn(ALine: Integer; out AColumn: Integer): Boolean;
var
  mIndex, mValue: Integer;
begin
  mValue := -1;
  mIndex := FFirst[FInfo[ALine].StatementLine];
  while (mIndex >= 0) and (mIndex <= FLast[ALine]) do
  begin
    if FTokens[mIndex].IsSymbol(':=') and (mIndex < FLast[ALine]) then
    begin
      mValue := mIndex + 1;
    end
    else if (mValue < 0) and (FTokens[mIndex].Kind = TPascalTokenKind.StringLiteral) then
    begin
      mValue := mIndex;
    end;
    Inc(mIndex);
  end;
  Result := mValue >= 0;
  if Result then
  begin
    AColumn := VisualColumn(FTokens[mValue].StartPos.Line, FTokens[mValue].StartPos.Character);
  end;
end;

function TIndentScan.StartsWithCloser(ALine: Integer): Boolean;
var
  mWord: string;
begin
  Result := False;
  if (ALine < 0) or (FFirst[ALine] < 0) or (FTokens[FFirst[ALine]].Kind <> TPascalTokenKind.Keyword) then
  begin
    Exit;
  end;
  for mWord in cClosers do
  begin
    if FTokens[FFirst[ALine]].IsKeyword(mWord) then
    begin
      Exit(True);
    end;
  end;
end;

function TIndentScan.EndsInOpenString(ALine: Integer): Boolean;
var
  mToken: TPascalToken;
begin
  Result := (ALine >= 0) and (FLast[ALine] >= 0);
  if not Result then
  begin
    Exit;
  end;
  mToken := FTokens[FLast[ALine]];
  Result := (mToken.Kind = TPascalTokenKind.StringLiteral) and not mToken.Terminated and
    (mToken.StartPos.Line = ALine) and (Length(mToken.Text) > 1) and not mToken.Text.StartsWith('''''''');
end;

{ TEnterRun }

constructor TEnterRun.Create(const AText: string; ALine: Integer; const AOptions: TSmartIndentOptions);
begin
  inherited Create;
  FLine := ALine;
  FOptions := AOptions;
  FScan := TIndentScan.Create(AText, ALine, AOptions.IndentSize);
  FResult := Default(TSmartIndentResult);
end;

destructor TEnterRun.Destroy;
begin
  FScan.Free;
  inherited;
end;

function TEnterRun.IndentText(AColumn: Integer): string;
begin
  Result := TBlockIndenter.IndentText(AColumn, FScan.Step, FOptions.UseTabs);
end;

/// <summary>Einrückung der Zeile ALine auf AColumn, dahinter ASuffix; die Schreibmarke steht danach.</summary>
procedure TEnterRun.SetIndent(ALine, AColumn: Integer; const ASuffix: string);
var
  mLength: Integer;
  mText: string;
begin
  TBlockIndenter.LeadingColumns(FScan.Lines[ALine], FScan.Step, mLength);
  mText := IndentText(AColumn) + ASuffix;
  if (AColumn <> FScan.Columns[ALine]) or (ASuffix <> '') then
  begin
    FResult.Edits := FResult.Edits + [TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, mLength), mText)];
    mLength := Length(mText);
  end;
  if ALine = FLine then
  begin
    FResult.Cursor := TTextPosition.Create(ALine, mLength);
  end;
end;

function TEnterRun.SplitString: Boolean;
var
  mColumn, mAligned: Integer;
  mEnd: TTextPosition;
begin
  Result := FOptions.SplitStrings and FScan.EndsInOpenString(FLine - 1);
  if not Result then
  begin
    Exit;
  end;
  mColumn := FScan.Columns[FScan.Info[FLine - 1].StatementLine] + FScan.Step;
  if (FOptions.StringContinuation = TStringContinuation.Align) and
    (FScan.BracketColumn(FLine, mAligned) or FScan.ValueColumn(FLine - 1, mAligned)) then
  begin
    mColumn := mAligned;
  end;
  mEnd := FScan.Tokens[FScan.LastToken[FLine - 1]].EndPos;
  FResult.Edits := [TTextEdit.Create(TTextRange.Create(mEnd, mEnd), ''' +')];
  SetIndent(FLine, mColumn, '''');
end;

function TEnterRun.CloserColumn(out AColumn: Integer): Boolean;
begin
  Result := FOptions.OutdentClosers and FScan.StartsWithCloser(FLine - 1) and
    FScan.TargetColumn(FLine - 1, AColumn);
end;

function TEnterRun.NewLineColumn(ACloser: Boolean; ACloserColumn: Integer; out AColumn: Integer): Boolean;
begin
  if FOptions.AfterEnter then
  begin
    Result := FScan.TargetColumn(FLine, AColumn);
    if Result and ACloser then
    begin
      // Die Zeile darüber rückt; die neue Zeile folgt ihr, auch als Fortsetzung (end ohne Semikolon).
      Inc(AColumn, ACloserColumn - FScan.Columns[FLine - 1]);
    end;
    Exit;
  end;
  // Nur das Schlusswort: Die neue Zeile behält ihren Abstand zu ihm.
  Result := ACloser;
  AColumn := Max(FScan.Columns[FLine] + ACloserColumn - FScan.Columns[FLine - 1], 0);
end;

function TEnterRun.Reindent: Boolean;
var
  mCloser: Boolean;
  mCloserColumn, mColumn: Integer;
begin
  mCloser := CloserColumn(mCloserColumn);
  Result := NewLineColumn(mCloser, mCloserColumn, mColumn);
  if mCloser then
  begin
    SetIndent(FLine - 1, mCloserColumn, '');
  end;
  if Result then
  begin
    SetIndent(FLine, mColumn, '');
  end;
end;

function TEnterRun.Run(out AResult: TSmartIndentResult): Boolean;
begin
  Result := (FLine >= 1) and (FLine <= High(FScan.Lines)) and not FScan.InsideToken(FLine);
  if Result then
  begin
    Result := SplitString or Reindent;
  end;
  AResult := FResult;
end;

{ TSmartIndent }

class function TSmartIndent.AfterEnter(const AText: string; ALine: Integer; const AOptions: TSmartIndentOptions;
  out AResult: TSmartIndentResult): Boolean;
var
  mRun: TEnterRun;
begin
  mRun := TEnterRun.Create(AText, ALine, AOptions);
  try
    Result := mRun.Run(AResult);
  finally
    mRun.Free;
  end;
end;

class function TSmartIndent.ColumnAt(const AText: string; ALine, AIndentSize: Integer; out AColumn: Integer): Boolean;
var
  mScan: TIndentScan;
begin
  AColumn := 0;
  mScan := TIndentScan.Create(AText, ALine, AIndentSize);
  try
    Result := (ALine >= 0) and (ALine <= High(mScan.Lines)) and not mScan.InsideToken(ALine) and
      mScan.TargetColumn(ALine, AColumn);
  finally
    mScan.Free;
  end;
end;

end.
