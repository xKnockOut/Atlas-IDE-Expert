unit Atlas.Common.Editing.Formatter.Layout;

// Zeilenaufbau beim Formatieren (#43): begin und else in eigene Zeilen
// setzen bzw. hochziehen, untereinander stehende Zuweisungen, Deklarationen
// und Kommentare am Zeilenende ausrichten und lange Zeilen umbrechen. Jede
// Ausgabezeile merkt sich ihre Ursprungszeile, damit der Formatierer daraus
// Änderungen je Zeile bzw. Zeilenbereich macht und bei "Auswahl formatieren"
// nur Zeilen im Bereich anfasst. Mehrzeilige Tokens und asm-Blöcke bleiben.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract;

type
  TFormatLine = record
    Text: string;
    /// <summary>Zeile im ursprünglichen Text, aus der diese Zeile stammt.</summary>
    Origin: Integer;
  end;

  TFormatAlignment = (Assignments, Declarations, Constants, Comments);

  TFormatLayout = class
  public
    /// <summary>Zeilen, die in einem mehrzeiligen Token oder einem asm-Block liegen.</summary>
    class function FrozenLines(const ATokens: TArray<TPascalToken>; ACount: Integer): TArray<Boolean>; static;
    /// <summary>Stellung von begin und else nach AStyle; AJoined[L]: Zeile L wurde an die vorige gehängt.</summary>
    class function Place(const ALines: TArray<string>; const ATokens: TArray<TPascalToken>;
      const AStyle: TFormatStyle; AFirst, ALast: Integer; out AJoined: TArray<Boolean>): TArray<TFormatLine>; static;
    /// <summary>Richtet AKind in Gruppen untereinander stehender Zeilen aus; ATokens gehören zu ALines.</summary>
    class procedure Align(var ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
      AKind: TFormatAlignment; AFirst, ALast: Integer); static;
    /// <summary>Bricht Zeilen über AStyle.MaxLineLength einmal um; True, wenn sich etwas geändert hat.</summary>
    class function Wrap(var ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
      const AStyle: TFormatStyle; AFirst, ALast: Integer): Boolean; static;
    /// <summary>Text einer Einrückungsebene nach AStyle.</summary>
    class function IndentUnit(const AStyle: TFormatStyle): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines;

type
  TSplit = record
    Column: Integer;
    /// <summary>Die neue Zeile rückt eine Ebene tiefer ein (Anweisung hinter begin).</summary>
    Deeper: Boolean;
  end;

  /// <summary>Ergebnis der Suche nach der Lücke vor dem auszurichtenden Token an einer Stelle der Zeile.</summary>
  TGapScan = (Next, Found, Fail);

  /// <summary>Stellung von begin und else: Trennstellen je Zeile und an die vorige gehängte Zeilen.</summary>
  TBlockPlacing = class
  private
    FTokens: TArray<TPascalToken>;
    FStyle: TFormatStyle;
    FFirst: Integer;
    FLast: Integer;
    FFrozen: TArray<Boolean>;
    FSplits: TArray<TArray<TSplit>>;
    FJoined: TArray<Boolean>;
    function InRange(ALine: Integer): Boolean;
    function LastOnLine(AIndex: Integer): Boolean;
    function FirstOnLine(AIndex: Integer): Boolean;
    procedure AddSplit(ALine, AColumn: Integer; ADeeper: Boolean);
    function CanSplit(APrevious, AIndex: Integer): Boolean;
    function CanJoin(APrevious, AIndex: Integer): Boolean;
    procedure PlaceKeyword(APrevious, AIndex: Integer; APlacement: TBlockPlacement; ASplitBody: Boolean);
    procedure Mark(APrevious, AIndex: Integer);
    function PartIndent(const AIndent: string; const ASplit: TSplit): string;
    procedure SplitInto(AOutput: TList<TFormatLine>; const AText: string; ALine: Integer);
  public
    constructor Create(const ATokens: TArray<TPascalToken>; const AStyle: TFormatStyle; AFirst, ALast,
      ALineCount: Integer);
    /// <summary>Sucht die Stellen, an denen begin oder else getrennt bzw. hochgezogen wird.</summary>
    procedure MarkAll;
    /// <summary>ALines nach den gefundenen Stellen getrennt bzw. zusammengefügt.</summary>
    function Lines(const ALines: TArray<string>): TArray<TFormatLine>;
    property Joined: TArray<Boolean> read FJoined;
  end;

  /// <summary>Richtet eine Art (Zuweisungen, Deklarationen, Konstanten, Kommentare) in Gruppen untereinander
  /// stehender Zeilen aus.</summary>
  TAligning = class
  private
    FLines: TArray<TFormatLine>;
    FTokens: TArray<TPascalToken>;
    FKind: TFormatAlignment;
    FFirst: Integer;
    FLast: Integer;
    FFrozen: TArray<Boolean>;
    FByLine: TArray<TArray<Integer>>;
    FGapStart: TArray<Integer>;
    FGapEnd: TArray<Integer>;
    procedure SetGap(ALine, AStart, AEnd: Integer);
    function EndsWithSemicolon(const AItems: TArray<Integer>): Boolean;
    function CommentGap(ALine: Integer; const AItems: TArray<Integer>): Boolean;
    function AssignmentGap(ALine: Integer; const AItems: TArray<Integer>; APosition: Integer): TGapScan;
    function DeclarationGap(ALine: Integer; const AItems: TArray<Integer>; APosition: Integer): TGapScan;
    function ConstantGap(ALine: Integer; const AItems: TArray<Integer>; APosition: Integer): TGapScan;
    function GapAt(ALine: Integer; const AItems: TArray<Integer>; APosition: Integer): TGapScan;
    function CodeGap(ALine: Integer; const AItems: TArray<Integer>): Boolean;
    function Fits(ALine: Integer): Boolean;
    function SameGroup(AGroupStart, ALine: Integer): Boolean;
    procedure Flush(AFrom, ATo: Integer);
  public
    constructor Create(const ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
      AKind: TFormatAlignment; AFirst, ALast: Integer);
    procedure Run;
    property Lines: TArray<TFormatLine> read FLines;
  end;

const
  cWrapOperators: array[0..11] of string = ('+', '-', '*', '/', 'and', 'or', 'xor', 'div', 'mod', 'shl', 'shr',
    '<>');

function IsCode(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

/// <summary>Tokens je Zeile (Zeile des Anfangs).</summary>
function TokensByLine(const ATokens: TArray<TPascalToken>; ACount: Integer): TArray<TArray<Integer>>;
var
  mIndex, mLine: Integer;
begin
  SetLength(Result, ACount);
  for mIndex := 0 to High(ATokens) do
  begin
    mLine := ATokens[mIndex].StartPos.Line;
    if (mLine >= 0) and (mLine < ACount) then
    begin
      Result[mLine] := Result[mLine] + [mIndex];
    end;
  end;
end;

/// <summary>+1 für eine öffnende, -1 für eine schließende Klammer, sonst 0.</summary>
function BracketDelta(const AToken: TPascalToken): Integer;
begin
  Result := 0;
  if AToken.IsSymbol('(') or AToken.IsSymbol('[') then
  begin
    Result := 1;
  end
  else if AToken.IsSymbol(')') or AToken.IsSymbol(']') then
  begin
    Result := -1;
  end;
end;

{ TBlockPlacing }

constructor TBlockPlacing.Create(const ATokens: TArray<TPascalToken>; const AStyle: TFormatStyle; AFirst, ALast,
  ALineCount: Integer);
begin
  inherited Create;
  FTokens := ATokens;
  FStyle := AStyle;
  FFirst := AFirst;
  FLast := ALast;
  SetLength(FJoined, ALineCount);
  SetLength(FSplits, ALineCount);
  FFrozen := TFormatLayout.FrozenLines(ATokens, ALineCount);
end;

function TBlockPlacing.InRange(ALine: Integer): Boolean;
begin
  Result := (ALine >= FFirst) and (ALine <= FLast) and not FFrozen[ALine];
end;

/// <summary>Ist AIndex das letzte Token seiner Zeile (auch ohne Kommentar dahinter)?</summary>
function TBlockPlacing.LastOnLine(AIndex: Integer): Boolean;
begin
  Result := (AIndex = High(FTokens)) or (FTokens[AIndex + 1].StartPos.Line > FTokens[AIndex].EndPos.Line);
end;

function TBlockPlacing.FirstOnLine(AIndex: Integer): Boolean;
begin
  Result := (AIndex = 0) or (FTokens[AIndex - 1].EndPos.Line < FTokens[AIndex].StartPos.Line);
end;

procedure TBlockPlacing.AddSplit(ALine, AColumn: Integer; ADeeper: Boolean);
var
  mSplit: TSplit;
begin
  mSplit.Column := AColumn;
  mSplit.Deeper := ADeeper;
  FSplits[ALine] := FSplits[ALine] + [mSplit];
end;

/// <summary>Das Token AIndex folgt in derselben Zeile direkt auf APrevious und darf abgetrennt werden.</summary>
function TBlockPlacing.CanSplit(APrevious, AIndex: Integer): Boolean;
var
  mLine: Integer;
begin
  mLine := FTokens[AIndex].StartPos.Line;
  Result := (FTokens[APrevious].EndPos.Line = mLine) and InRange(mLine) and (APrevious = AIndex - 1);
end;

/// <summary>Das Token AIndex beginnt die Zeile hinter APrevious, das seine Zeile beendet, und darf hochgezogen
/// werden.</summary>
function TBlockPlacing.CanJoin(APrevious, AIndex: Integer): Boolean;
var
  mLine: Integer;
begin
  mLine := FTokens[AIndex].StartPos.Line;
  Result := (FTokens[APrevious].EndPos.Line = mLine - 1) and FirstOnLine(AIndex) and LastOnLine(APrevious);
  Result := Result and InRange(mLine) and InRange(mLine - 1) and (FSplits[mLine] = nil);
end;

procedure TBlockPlacing.PlaceKeyword(APrevious, AIndex: Integer; APlacement: TBlockPlacement; ASplitBody: Boolean);
var
  mLine: Integer;
begin
  mLine := FTokens[AIndex].StartPos.Line;
  if (APlacement = TBlockPlacement.NewLine) and CanSplit(APrevious, AIndex) then
  begin
    AddSplit(mLine, FTokens[AIndex].StartPos.Character, False);
    // Was hinter begin steht, kommt in eine eigene Zeile.
    if ASplitBody and (AIndex < High(FTokens)) and (FTokens[AIndex + 1].StartPos.Line = mLine) and
      IsCode(FTokens[AIndex + 1]) then
    begin
      AddSplit(mLine, FTokens[AIndex + 1].StartPos.Character, True);
    end;
  end
  else if (APlacement = TBlockPlacement.SameLine) and CanJoin(APrevious, AIndex) then
  begin
    // Auch an eine schon angehängte Zeile: "end" + "else" + "begin" werden in einem Lauf eine Zeile, sonst
    // erst im zweiten (#1358, Stabilität).
    FJoined[mLine] := True;
  end;
end;

/// <summary>begin hinter then, else oder do und else hinter end.</summary>
procedure TBlockPlacing.Mark(APrevious, AIndex: Integer);
var
  mWord, mPrevious: string;
begin
  if (FTokens[AIndex].Kind <> TPascalTokenKind.Keyword) or (FTokens[APrevious].Kind <> TPascalTokenKind.Keyword) then
  begin
    Exit;
  end;
  mWord := LowerCase(FTokens[AIndex].Text);
  mPrevious := LowerCase(FTokens[APrevious].Text);
  if (mWord = 'begin') and MatchStr(mPrevious, ['then', 'else', 'do']) then
  begin
    PlaceKeyword(APrevious, AIndex, FStyle.BeginPlacement, True);
  end
  else if (mWord = 'else') and (mPrevious = 'end') then
  begin
    PlaceKeyword(APrevious, AIndex, FStyle.ElsePlacement, False);
  end;
end;

procedure TBlockPlacing.MarkAll;
var
  mIndex, mPrevious: Integer;
begin
  mPrevious := -1;
  for mIndex := 0 to High(FTokens) do
  begin
    if not IsCode(FTokens[mIndex]) then
    begin
      Continue;
    end;
    if mPrevious >= 0 then
    begin
      Mark(mPrevious, mIndex);
    end;
    mPrevious := mIndex;
  end;
end;

function TBlockPlacing.PartIndent(const AIndent: string; const ASplit: TSplit): string;
begin
  Result := AIndent;
  if ASplit.Deeper then
  begin
    Result := TFormatLayout.IndentUnit(FStyle) + Result;
  end;
end;

/// <summary>Zeile ALine mit dem Text AText, an ihren Trennstellen in Teile zerlegt.</summary>
procedure TBlockPlacing.SplitInto(AOutput: TList<TFormatLine>; const AText: string; ALine: Integer);
var
  mItem: TFormatLine;
  mIndent: string;
  mColumn, mPart: Integer;
begin
  mItem.Origin := ALine;
  mItem.Text := AText;
  if FSplits[ALine] = nil then
  begin
    AOutput.Add(mItem);
    Exit;
  end;
  mIndent := TTextLines.IndentOf(AText);
  mColumn := 0;
  for mPart := 0 to High(FSplits[ALine]) do
  begin
    mItem.Text := TrimRight(Copy(AText, mColumn + 1, FSplits[ALine][mPart].Column - mColumn));
    if mPart > 0 then
    begin
      mItem.Text := PartIndent(mIndent, FSplits[ALine][mPart - 1]) + TrimLeft(mItem.Text);
    end;
    if Trim(mItem.Text) <> '' then
    begin
      AOutput.Add(mItem);
    end;
    mColumn := FSplits[ALine][mPart].Column;
  end;
  mItem.Text := PartIndent(mIndent, FSplits[ALine][High(FSplits[ALine])]) + TrimLeft(Copy(AText, mColumn + 1, MaxInt));
  AOutput.Add(mItem);
end;

function TBlockPlacing.Lines(const ALines: TArray<string>): TArray<TFormatLine>;
var
  mOutput: TList<TFormatLine>;
  mItem: TFormatLine;
  mLine: Integer;
begin
  mOutput := TList<TFormatLine>.Create;
  try
    for mLine := 0 to High(ALines) do
    begin
      if FJoined[mLine] and (mOutput.Count > 0) then
      begin
        mItem := mOutput[mOutput.Count - 1];
        mItem.Text := TrimRight(mItem.Text) + ' ' + TrimLeft(ALines[mLine]);
        mOutput[mOutput.Count - 1] := mItem;
      end
      else
      begin
        SplitInto(mOutput, ALines[mLine], mLine);
      end;
    end;
    Result := mOutput.ToArray;
  finally
    mOutput.Free;
  end;
end;

{ TAligning }

constructor TAligning.Create(const ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
  AKind: TFormatAlignment; AFirst, ALast: Integer);
begin
  inherited Create;
  FLines := ALines;
  FTokens := ATokens;
  FKind := AKind;
  FFirst := AFirst;
  FLast := ALast;
  FFrozen := TFormatLayout.FrozenLines(ATokens, Length(ALines));
  FByLine := TokensByLine(ATokens, Length(ALines));
  SetLength(FGapStart, Length(ALines));
  SetLength(FGapEnd, Length(ALines));
end;

procedure TAligning.SetGap(ALine, AStart, AEnd: Integer);
begin
  FGapStart[ALine] := AStart;
  FGapEnd[ALine] := AEnd;
end;

function TAligning.EndsWithSemicolon(const AItems: TArray<Integer>): Boolean;
begin
  Result := FTokens[AItems[High(AItems)]].IsSymbol(';');
end;

/// <summary>Kommentar mit // am Ende einer Codezeile.</summary>
function TAligning.CommentGap(ALine: Integer; const AItems: TArray<Integer>): Boolean;
var
  mPosition: Integer;
  mToken: TPascalToken;
begin
  mPosition := High(AItems);
  mToken := FTokens[AItems[mPosition]];
  Result := (mPosition > 0) and (mToken.Kind = TPascalTokenKind.Comment) and StartsStr('//', mToken.Text) and
    (FTokens[AItems[mPosition - 1]].EndPos.Line = ALine);
  if Result then
  begin
    SetGap(ALine, FTokens[AItems[mPosition - 1]].EndPos.Character, mToken.StartPos.Character);
  end;
end;

function TAligning.AssignmentGap(ALine: Integer; const AItems: TArray<Integer>; APosition: Integer): TGapScan;
var
  mToken: TPascalToken;
begin
  mToken := FTokens[AItems[APosition]];
  if mToken.IsSymbol(':=') then
  begin
    SetGap(ALine, FTokens[AItems[APosition - 1]].EndPos.Character, mToken.StartPos.Character);
    Exit(TGapScan.Found);
  end;
  Result := TGapScan.Fail;
  if mToken.IsSymbol('.') or mToken.IsSymbol(']') or mToken.IsSymbol('^') or
    (mToken.Kind = TPascalTokenKind.Identifier) then
  begin
    Result := TGapScan.Next;
  end;
end;

function TAligning.DeclarationGap(ALine: Integer; const AItems: TArray<Integer>; APosition: Integer): TGapScan;
var
  mToken: TPascalToken;
begin
  mToken := FTokens[AItems[APosition]];
  if mToken.IsSymbol(':') and (APosition < High(AItems)) then
  begin
    // Ausgerichtet wird der Typ hinter dem Doppelpunkt; nur ganze Deklarationen mit ;.
    if not EndsWithSemicolon(AItems) then
    begin
      Exit(TGapScan.Fail);
    end;
    SetGap(ALine, mToken.EndPos.Character, FTokens[AItems[APosition + 1]].StartPos.Character);
    Exit(TGapScan.Found);
  end;
  Result := TGapScan.Fail;
  if mToken.IsSymbol(',') or (mToken.Kind = TPascalTokenKind.Identifier) then
  begin
    Result := TGapScan.Next;
  end;
end;

function TAligning.ConstantGap(ALine: Integer; const AItems: TArray<Integer>; APosition: Integer): TGapScan;
var
  mToken: TPascalToken;
begin
  mToken := FTokens[AItems[APosition]];
  Result := TGapScan.Fail;
  if (APosition = 1) and mToken.IsSymbol('=') and EndsWithSemicolon(AItems) then
  begin
    SetGap(ALine, FTokens[AItems[0]].EndPos.Character, mToken.StartPos.Character);
    Result := TGapScan.Found;
  end;
end;

function TAligning.GapAt(ALine: Integer; const AItems: TArray<Integer>; APosition: Integer): TGapScan;
begin
  case FKind of
    TFormatAlignment.Assignments:
      Result := AssignmentGap(ALine, AItems, APosition);
    TFormatAlignment.Declarations:
      Result := DeclarationGap(ALine, AItems, APosition);
    TFormatAlignment.Constants:
      Result := ConstantGap(ALine, AItems, APosition);
  else
    // Kommentare sucht CommentGap.
    Result := TGapScan.Next;
  end;
end;

/// <summary>Lücke vor := (Zuweisungen), vor dem Typ (Deklarationen) oder vor = (Konstanten) auf der obersten
/// Klammerebene einer Zeile, die mit einem Bezeichner beginnt.</summary>
function TAligning.CodeGap(ALine: Integer; const AItems: TArray<Integer>): Boolean;
var
  mPosition, mDepth: Integer;
  mScan: TGapScan;
begin
  Result := False;
  mDepth := 0;
  for mPosition := 1 to High(AItems) do
  begin
    if FTokens[AItems[mPosition]].Kind = TPascalTokenKind.Comment then
    begin
      Exit;
    end;
    Inc(mDepth, BracketDelta(FTokens[AItems[mPosition]]));
    if mDepth > 0 then
    begin
      Continue;
    end;
    mScan := GapAt(ALine, AItems, mPosition);
    if mScan <> TGapScan.Next then
    begin
      Exit(mScan = TGapScan.Found);
    end;
  end;
end;

/// <summary>Lücke vor dem auszurichtenden Token der Zeile merken; False, wenn die Zeile nicht passt.</summary>
function TAligning.Fits(ALine: Integer): Boolean;
var
  mItems: TArray<Integer>;
begin
  Result := False;
  if (FLines[ALine].Origin < FFirst) or (FLines[ALine].Origin > FLast) or FFrozen[ALine] then
  begin
    Exit;
  end;
  mItems := FByLine[ALine];
  if mItems = nil then
  begin
    Exit;
  end;
  if FKind = TFormatAlignment.Comments then
  begin
    Result := CommentGap(ALine, mItems);
  end
  else if FTokens[mItems[0]].Kind = TPascalTokenKind.Identifier then
  begin
    Result := CodeGap(ALine, mItems);
  end;
end;

/// <summary>Eine Gruppe: aufeinanderfolgende passende Zeilen gleicher Einrückung (Kommentare: beliebige).</summary>
function TAligning.SameGroup(AGroupStart, ALine: Integer): Boolean;
begin
  Result := (FKind = TFormatAlignment.Comments) or
    (TTextLines.IndentOf(FLines[ALine].Text) = TTextLines.IndentOf(FLines[AGroupStart].Text));
end;

procedure TAligning.Flush(AFrom, ATo: Integer);
var
  mItem, mTarget: Integer;
begin
  if ATo - AFrom < 1 then
  begin
    Exit;
  end;
  mTarget := 0;
  for mItem := AFrom to ATo do
  begin
    mTarget := Max(mTarget, FGapStart[mItem] + 1);
  end;
  for mItem := AFrom to ATo do
  begin
    FLines[mItem].Text := Copy(FLines[mItem].Text, 1, FGapStart[mItem]) +
      StringOfChar(' ', mTarget - FGapStart[mItem]) + Copy(FLines[mItem].Text, FGapEnd[mItem] + 1, MaxInt);
  end;
end;

procedure TAligning.Run;
var
  mLine, mGroupStart: Integer;
  mFits: Boolean;
begin
  mGroupStart := -1;
  for mLine := 0 to High(FLines) + 1 do
  begin
    mFits := (mLine <= High(FLines)) and Fits(mLine);
    if mFits and (mGroupStart >= 0) and SameGroup(mGroupStart, mLine) then
    begin
      Continue;
    end;
    if mGroupStart >= 0 then
    begin
      Flush(mGroupStart, mLine - 1);
    end;
    mGroupStart := -1;
    if mFits then
    begin
      mGroupStart := mLine;
    end;
  end;
end;

{ Umbrechen }

function IsOperand(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number, TPascalTokenKind.StringLiteral,
    TPascalTokenKind.CharLiteral]) or AToken.IsSymbol(')') or AToken.IsSymbol(']');
end;

/// <summary>Umbruch vor AToken: hinter einem Komma oder vor einem zweistelligen Operator.</summary>
function IsBreakPoint(const APrevious, AToken: TPascalToken): Boolean;
begin
  Result := APrevious.IsSymbol(',') or (MatchText(AToken.Text, cWrapOperators) and IsOperand(APrevious));
end;

/// <summary>Letzte Stelle in AItems (Tokens der Zeile ALine mit dem Text AText), vor der umgebrochen werden kann,
/// ohne dass der Teil davor länger als AMaxLength wird; -1 ohne.</summary>
function BreakPosition(const AText: string; ALine: Integer; const ATokens: TArray<TPascalToken>;
  const AItems: TArray<Integer>; AMaxLength: Integer): Integer;
var
  mPosition: Integer;
  mToken: TPascalToken;
  mLeft: string;
begin
  Result := -1;
  if (Length(AItems) <= 1) or not IsCode(ATokens[AItems[0]]) then
  begin
    Exit;
  end;
  for mPosition := 1 to High(AItems) do
  begin
    mToken := ATokens[AItems[mPosition]];
    mLeft := TrimRight(Copy(AText, 1, mToken.StartPos.Character));
    if (mToken.EndPos.Line <> ALine) or (Length(mLeft) > AMaxLength) then
    begin
      Break;
    end;
    if (mToken.Kind <> TPascalTokenKind.Comment) and IsBreakPoint(ATokens[AItems[mPosition - 1]], mToken) and
      (Trim(mLeft) <> '') then
    begin
      Result := mPosition;
    end;
  end;
end;

{ TFormatLayout }

class function TFormatLayout.IndentUnit(const AStyle: TFormatStyle): string;
begin
  if AStyle.UseTabs then
  begin
    Result := #9;
  end
  else
  begin
    Result := StringOfChar(' ', Max(AStyle.IndentSize, 1));
  end;
end;

class function TFormatLayout.FrozenLines(const ATokens: TArray<TPascalToken>; ACount: Integer): TArray<Boolean>;
var
  mIndex, mLine, mAsmDepth: Integer;
  mToken: TPascalToken;
begin
  SetLength(Result, ACount);
  mAsmDepth := 0;
  for mIndex := 0 to High(ATokens) do
  begin
    mToken := ATokens[mIndex];
    for mLine := mToken.StartPos.Line + 1 to Min(mToken.EndPos.Line, ACount - 1) do
    begin
      Result[mLine] := True;
    end;
    if (mToken.Kind = TPascalTokenKind.Keyword) and mToken.IsKeyword('asm') then
    begin
      Inc(mAsmDepth);
    end
    else if (mAsmDepth > 0) and (mToken.Kind = TPascalTokenKind.Keyword) and mToken.IsKeyword('end') then
    begin
      Dec(mAsmDepth);
    end
    else if (mAsmDepth > 0) and (mToken.StartPos.Line < ACount) then
    begin
      Result[mToken.StartPos.Line] := True;
    end;
  end;
end;

class function TFormatLayout.Place(const ALines: TArray<string>; const ATokens: TArray<TPascalToken>;
  const AStyle: TFormatStyle; AFirst, ALast: Integer; out AJoined: TArray<Boolean>): TArray<TFormatLine>;
var
  mPlacing: TBlockPlacing;
begin
  mPlacing := TBlockPlacing.Create(ATokens, AStyle, AFirst, ALast, Length(ALines));
  try
    mPlacing.MarkAll;
    Result := mPlacing.Lines(ALines);
    AJoined := mPlacing.Joined;
  finally
    mPlacing.Free;
  end;
end;

class procedure TFormatLayout.Align(var ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
  AKind: TFormatAlignment; AFirst, ALast: Integer);
var
  mAligning: TAligning;
begin
  mAligning := TAligning.Create(ALines, ATokens, AKind, AFirst, ALast);
  try
    mAligning.Run;
    ALines := mAligning.Lines;
  finally
    mAligning.Free;
  end;
end;

class function TFormatLayout.Wrap(var ALines: TArray<TFormatLine>; const ATokens: TArray<TPascalToken>;
  const AStyle: TFormatStyle; AFirst, ALast: Integer): Boolean;
var
  mFrozen: TArray<Boolean>;
  mByLine: TArray<TArray<Integer>>;
  mOutput: TList<TFormatLine>;
  mLine, mBest, mColumn: Integer;
  mItem: TFormatLine;
begin
  Result := False;
  if AStyle.MaxLineLength <= 0 then
  begin
    Exit;
  end;
  mFrozen := FrozenLines(ATokens, Length(ALines));
  mByLine := TokensByLine(ATokens, Length(ALines));
  mOutput := TList<TFormatLine>.Create;
  try
    for mLine := 0 to High(ALines) do
    begin
      mItem := ALines[mLine];
      mBest := -1;
      if (Length(mItem.Text) > AStyle.MaxLineLength) and (mItem.Origin >= AFirst) and (mItem.Origin <= ALast) and
        not mFrozen[mLine] then
      begin
        mBest := BreakPosition(mItem.Text, mLine, ATokens, mByLine[mLine], AStyle.MaxLineLength);
      end;
      if mBest < 0 then
      begin
        mOutput.Add(mItem);
        Continue;
      end;
      mColumn := ATokens[mByLine[mLine][mBest]].StartPos.Character;
      mItem.Text := TrimRight(Copy(ALines[mLine].Text, 1, mColumn));
      mOutput.Add(mItem);
      mItem.Text := TTextLines.IndentOf(ALines[mLine].Text) + IndentUnit(AStyle) +
        TrimLeft(Copy(ALines[mLine].Text, mColumn + 1, MaxInt));
      mOutput.Add(mItem);
      Result := True;
    end;
    if Result then
    begin
      ALines := mOutput.ToArray;
    end;
  finally
    mOutput.Free;
  end;
end;

end.
