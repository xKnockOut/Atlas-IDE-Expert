unit Atlas.Common.Rules.Builtin.Testing.TestCaseTrivia;

// Kommentare und bedingte Direktiven um die [TestCase]-Attribute einer Testmethode, damit die TestCase-Tabelle
// (Atlas.Common.Rules.Builtin.Testing.TestCaseTable) sie beim Schreiben mitnimmt.
//   - Jedes Attribut vom ersten bis zum letzten [TestCase] bekommt, was um es herum steht: eigene Zeilen davor
//     (Leading), Text in seiner Zeile davor (Prefix) und dahinter (Trailing) und eigene Zeilen danach (After).
//     Zwischen zwei Attributen gehört, was in der Zeile des ersten steht, zu diesem (Kommentar am Zeilenende);
//     alle übrigen Zeilen gehören zum zweiten, nur Zeilen bis zum letzten {$ENDIF} gehören noch zum ersten.
//   - Über dem ersten [TestCase] gehören die Zeilen dazu, die direkt darüber stehen und nur Kommentare
//     enthalten; hinter dem letzten der Rest seiner Zeile, wenn er nur aus Kommentaren besteht. Ein
//     Doku-Kommentar /// beendet den Weg nach oben: Er gehört zur Methode und bleibt beim Löschen und
//     Verschieben der Fälle stehen.
//   - Bedingte Direktiven ({$IFDEF}, {$IF}, {$IFNDEF}, {$IFOPT} … {$ENDIF}, {$IFEND}) sind erlaubt, wenn jede
//     genau ein Attribut umschließt: Sie wandern dann mit ihm. Die öffnende Direktive darf über dem ersten
//     bzw. die schließende unter dem letzten Fall stehen. Alles andere ({$ELSE}, eine Bedingung über mehreren
//     Fällen, Schalter wie {$R+}) lässt sich nicht sicher erhalten: Problem nennt dann den Grund, und die
//     Tabelle bleibt nur lesbar. Der Baum enthält auch die Attribute inaktiver Zweige; ein Fall in
//     {$IFDEF NIE} … {$ENDIF} ist deshalb ein Fall mit seiner Bedingung wie jeder andere.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Text.Lines;

type
{$SCOPEDENUMS ON}
  /// <summary>Warum sich das Umfeld nicht erhalten lässt: Code (kein Kommentar, keine Direktive) oder eine
  /// Direktive, die nicht genau ein Attribut umschließt.</summary>
  TTriviaProblem = (None, Code, Directive);
{$SCOPEDENUMS OFF}

  /// <summary>Kommentare und Direktiven, die zu einem Attribut gehören, jeweils wie geschrieben.</summary>
  TAttributeTrivia = record
    /// <summary>Eigene Zeilen vor dem Attribut.</summary>
    Leading: TArray<string>;
    /// <summary>In der Zeile des Attributs davor; '' ohne.</summary>
    Prefix: string;
    /// <summary>In der Zeile des Attributs dahinter; '' ohne.</summary>
    Trailing: string;
    /// <summary>Eigene Zeilen hinter dem Attribut ({$ENDIF}).</summary>
    After: TArray<string>;
    /// <summary>Das Attribut AAttribute mit seinem Umfeld; Zeilen getrennt durch ALineEnd und AIndent.</summary>
    function Wrap(const AAttribute, ALineEnd, AIndent: string): string;
    /// <summary>Endet das Umfeld mit einem Kommentar //, hinter dem in der Zeile nichts mehr stehen darf?
    /// </summary>
    function EndsWithLineComment: Boolean;
  end;

  /// <summary>Umfeld der Attribute einer Methode.</summary>
  TTriviaBinding = record
    /// <summary>Je Attribut eins, in der Reihenfolge der Attribute.</summary>
    Items: TArray<TAttributeTrivia>;
    /// <summary>Bereich vom ersten bis zum letzten Attribut samt dem Umfeld davor und danach.</summary>
    Range: TTextRange;
    /// <summary>Steht hinter Range in derselben Zeile noch Text?</summary>
    CodeAfter: Boolean;
    Problem: TTriviaProblem;
  end;

  TTestCaseTrivia = class
  public
    /// <summary>Ordnet Kommentare und Direktiven den Attributen AAttributes (erstes bis letztes [TestCase], in
    /// der Reihenfolge der Datei) zu. ALines gehört zu AText.</summary>
    class function Bind(const AText: string; const ALines: TLineTable;
      const AAttributes: TArray<TSyntaxNode>): TTriviaBinding; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer;

type
  /// <summary>Kommentare und Direktiven ohne Leerzeile dazwischen: Jedes Token beginnt in der Zeile, in der das
  /// vorige endet.</summary>
  TChunk = record
    Text: string;
    StartOffset, EndOffset: Integer;
    StartLine, EndLine: Integer;
    Openers, Closers, Others: Integer;
    /// <summary>Kleinster Stand von öffnenden minus schließenden Direktiven innerhalb des Stücks.</summary>
    Lowest: Integer;
  end;

  /// <summary>Gezählte Direktiven eines Attributs: vor ihm (Leading, Prefix) und hinter ihm.</summary>
  TItemCount = record
    OpenBefore, CloseBefore, OpenAfter, CloseAfter, Others: Integer;
  end;

  TTriviaBinder = record
    Text: string;
    Lines: TLineTable;
    Attributes: TArray<TSyntaxNode>;
    Binding: TTriviaBinding;
    Counts: TArray<TItemCount>;
    /// <summary>Kommentare und Direktiven zwischen den Attributen, je Lücke.</summary>
    Gaps: TArray<TArray<TChunk>>;
    StartOffset, EndOffset: Integer;
    procedure Fail(AProblem: TTriviaProblem);
    procedure AddBefore(AIndex: Integer; const AChunk: TChunk; AOwnLine: Boolean);
    procedure AddAfter(AIndex: Integer; const AChunk: TChunk; AOwnLine: Boolean);
    procedure ReadGaps;
    procedure AssignGap(AIndex: Integer);
    procedure Balance(out ADeficit, ANet: Integer);
    procedure BindAbove(ADeficit: Integer; out AIncluded: Integer);
    procedure BindBelow(ANeeded: Integer);
    procedure Check;
  end;

{ TAttributeTrivia }

function TAttributeTrivia.Wrap(const AAttribute, ALineEnd, AIndent: string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in Leading do
  begin
    Result := Result + mLine + ALineEnd + AIndent;
  end;
  if Prefix <> '' then
  begin
    Result := Result + Prefix + ' ';
  end;
  Result := Result + AAttribute;
  if Trailing <> '' then
  begin
    Result := Result + ' ' + Trailing;
  end;
  for mLine in After do
  begin
    Result := Result + ALineEnd + AIndent + mLine;
  end;
end;

function TAttributeTrivia.EndsWithLineComment: Boolean;
var
  mLast: string;
  mTokens: TArray<TPascalToken>;
begin
  if After <> nil then
  begin
    mLast := After[High(After)];
  end
  else
  begin
    mLast := Trailing;
  end;
  mTokens := TPascalLexer.Tokenize(mLast);
  Result := (mTokens <> nil) and (mTokens[High(mTokens)].Kind = TPascalTokenKind.Comment) and
    StartsStr('//', mTokens[High(mTokens)].Text);
end;

{ Stücke }

type
{$SCOPEDENUMS ON}
  TDirectiveKind = (Open, Close, Other);
{$SCOPEDENUMS OFF}

function DirectiveKind(const AToken: TPascalToken): TDirectiveKind;
var
  mName: string;
begin
  mName := TPascalLexer.DirectiveName(AToken.Text);
  if MatchText(mName, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
  begin
    Result := TDirectiveKind.Open;
  end
  else if MatchText(mName, ['ENDIF', 'IFEND']) then
  begin
    Result := TDirectiveKind.Close;
  end
  else
  begin
    Result := TDirectiveKind.Other;
  end;
end;

/// <summary>Zählt die Direktive AToken in AChunk.</summary>
procedure CountDirective(var AChunk: TChunk; const AToken: TPascalToken; var ALevel: Integer);
begin
  case DirectiveKind(AToken) of
    TDirectiveKind.Open:
      begin
        Inc(AChunk.Openers);
        Inc(ALevel);
      end;
    TDirectiveKind.Close:
      begin
        Inc(AChunk.Closers);
        Dec(ALevel);
        if ALevel < AChunk.Lowest then
        begin
          AChunk.Lowest := ALevel;
        end;
      end;
  else
    Inc(AChunk.Others);
  end;
end;

/// <summary>Kommentare und Direktiven von AFrom bis ATo (Offsets ab 0) als Stücke; False, wenn dort anderes
/// steht oder ein Kommentar nicht abgeschlossen ist.</summary>
function ReadChunks(const AText: string; const ALines: TLineTable; AFrom, ATo: Integer;
  out AChunks: TArray<TChunk>): Boolean;
var
  mToken: TPascalToken;
  mChunk: TChunk;
  mStart, mEnd, mLevel: Integer;
begin
  AChunks := nil;
  mLevel := 0;
  for mToken in TPascalLexer.Tokenize(Copy(AText, AFrom + 1, ATo - AFrom)) do
  begin
    if not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) or not mToken.Terminated then
    begin
      Exit(False);
    end;
    mStart := AFrom + mToken.Offset;
    mEnd := mStart + Length(mToken.Text);
    if (AChunks <> nil) and (ALines.PositionAt(mStart).Line = AChunks[High(AChunks)].EndLine) then
    begin
      mChunk := AChunks[High(AChunks)];
      SetLength(AChunks, Length(AChunks) - 1);
    end
    else
    begin
      mChunk := Default(TChunk);
      mChunk.StartOffset := mStart;
      mChunk.StartLine := ALines.PositionAt(mStart).Line;
      mLevel := 0;
    end;
    mChunk.EndOffset := mEnd;
    mChunk.EndLine := ALines.PositionAt(mEnd).Line;
    mChunk.Text := Copy(AText, mChunk.StartOffset + 1, mEnd - mChunk.StartOffset);
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      CountDirective(mChunk, mToken, mLevel);
    end;
    AChunks := AChunks + [mChunk];
  end;
  Result := True;
end;

/// <summary>Das einzige Stück der Zeile ALine; False bei leerer Zeile oder anderem Text.</summary>
function LineChunk(const AText: string; const ALines: TLineTable; ALine: Integer; out AChunk: TChunk): Boolean;
var
  mChunks: TArray<TChunk>;
begin
  AChunk := Default(TChunk);
  Result := ReadChunks(AText, ALines, ALines.LineStart(ALine), ALines.LineContentEnd(ALine), mChunks) and
    (Length(mChunks) = 1) and (mChunks[0].EndLine = ALine);
  if Result then
  begin
    AChunk := mChunks[0];
  end;
end;

{ TTriviaBinder }

procedure TTriviaBinder.Fail(AProblem: TTriviaProblem);
begin
  if Binding.Problem = TTriviaProblem.None then
  begin
    Binding.Problem := AProblem;
  end;
end;

procedure TTriviaBinder.AddBefore(AIndex: Integer; const AChunk: TChunk; AOwnLine: Boolean);
begin
  if AOwnLine then
  begin
    Binding.Items[AIndex].Leading := Binding.Items[AIndex].Leading + [AChunk.Text];
  end
  else
  begin
    Binding.Items[AIndex].Prefix := AChunk.Text;
  end;
  Inc(Counts[AIndex].OpenBefore, AChunk.Openers);
  Inc(Counts[AIndex].CloseBefore, AChunk.Closers);
  Inc(Counts[AIndex].Others, AChunk.Others);
end;

procedure TTriviaBinder.AddAfter(AIndex: Integer; const AChunk: TChunk; AOwnLine: Boolean);
begin
  if AOwnLine then
  begin
    Binding.Items[AIndex].After := Binding.Items[AIndex].After + [AChunk.Text];
  end
  else
  begin
    Binding.Items[AIndex].Trailing := AChunk.Text;
  end;
  Inc(Counts[AIndex].OpenAfter, AChunk.Openers);
  Inc(Counts[AIndex].CloseAfter, AChunk.Closers);
  Inc(Counts[AIndex].Others, AChunk.Others);
end;

procedure TTriviaBinder.ReadGaps;
var
  mIndex: Integer;
begin
  SetLength(Gaps, Length(Attributes) - 1);
  for mIndex := 0 to High(Attributes) - 1 do
  begin
    if not ReadChunks(Text, Lines, Attributes[mIndex].EndOffset, Attributes[mIndex + 1].StartOffset,
      Gaps[mIndex]) then
    begin
      Fail(TTriviaProblem.Code);
    end;
  end;
end;

procedure TTriviaBinder.AssignGap(AIndex: Integer);
var
  mChunks: TArray<TChunk>;
  mIndex, mLastCloser: Integer;
begin
  mChunks := Gaps[AIndex];
  // Bis zum letzten Stück mit {$ENDIF} in eigener Zeile gehört alles noch zum vorigen Attribut.
  mLastCloser := -1;
  for mIndex := 0 to High(mChunks) do
  begin
    if (mChunks[mIndex].Closers > 0) and (mChunks[mIndex].StartLine > Attributes[AIndex].EndPos.Line) and
      (mChunks[mIndex].EndLine < Attributes[AIndex + 1].StartPos.Line) then
    begin
      mLastCloser := mIndex;
    end;
  end;
  for mIndex := 0 to High(mChunks) do
  begin
    if mChunks[mIndex].StartLine = Attributes[AIndex].EndPos.Line then
    begin
      AddAfter(AIndex, mChunks[mIndex], False);
    end
    else if mChunks[mIndex].EndLine = Attributes[AIndex + 1].StartPos.Line then
    begin
      AddBefore(AIndex + 1, mChunks[mIndex], False);
    end
    else if mIndex <= mLastCloser then
    begin
      AddAfter(AIndex, mChunks[mIndex], True);
    end
    else
    begin
      AddBefore(AIndex + 1, mChunks[mIndex], True);
    end;
  end;
end;

procedure TTriviaBinder.Balance(out ADeficit, ANet: Integer);
var
  mGap: TArray<TChunk>;
  mChunk: TChunk;
begin
  // ADeficit: so viele {$ENDIF} zwischen den Fällen schließen eine Bedingung, die vor dem ersten beginnt.
  ADeficit := 0;
  ANet := 0;
  for mGap in Gaps do
  begin
    for mChunk in mGap do
    begin
      if -(ANet + mChunk.Lowest) > ADeficit then
      begin
        ADeficit := -(ANet + mChunk.Lowest);
      end;
      ANet := ANet + mChunk.Openers - mChunk.Closers;
    end;
  end;
end;

/// <summary>Darf das Stück AChunk über dem ersten Fall dazugehören? Nur Kommentare und öffnende Direktiven,
/// diese nur bis zur Zahl AAllowed. Ein Doku-Kommentar /// gehört zur Methode, nicht zum ersten Fall.</summary>
function FitsAbove(const AChunk: TChunk; var AAllowed: Integer): Boolean;
begin
  Result := (AChunk.Others = 0) and (AChunk.Closers = 0) and (AChunk.Openers <= AAllowed) and
    not StartsStr('///', AChunk.Text);
  if Result then
  begin
    Dec(AAllowed, AChunk.Openers);
  end;
end;

procedure TTriviaBinder.BindAbove(ADeficit: Integer; out AIncluded: Integer);
var
  mFirst: TSyntaxNode;
  mChunks: TArray<TChunk>;
  mChunk: TChunk;
  mLine, mAllowed: Integer;
  mAbove: TArray<TChunk>;
begin
  mFirst := Attributes[0];
  mAllowed := ADeficit;
  StartOffset := mFirst.StartOffset;
  if not ReadChunks(Text, Lines, Lines.LineStart(mFirst.StartPos.Line), mFirst.StartOffset, mChunks) or
    (Length(mChunks) > 1) then
  begin
    AIncluded := 0;
    Exit;
  end;
  if mChunks <> nil then
  begin
    if not FitsAbove(mChunks[0], mAllowed) then
    begin
      AIncluded := 0;
      Exit;
    end;
    StartOffset := mChunks[0].StartOffset;
  end;
  mAbove := nil;
  mLine := mFirst.StartPos.Line - 1;
  while (mLine >= 0) and LineChunk(Text, Lines, mLine, mChunk) and FitsAbove(mChunk, mAllowed) do
  begin
    mAbove := [mChunk] + mAbove;
    StartOffset := mChunk.StartOffset;
    Dec(mLine);
  end;
  for mChunk in mAbove do
  begin
    AddBefore(0, mChunk, True);
  end;
  if mChunks <> nil then
  begin
    AddBefore(0, mChunks[0], False);
  end;
  AIncluded := ADeficit - mAllowed;
end;

procedure TTriviaBinder.BindBelow(ANeeded: Integer);
var
  mLast: TSyntaxNode;
  mChunks: TArray<TChunk>;
  mChunk: TChunk;
  mLine, mLastIndex: Integer;
begin
  mLast := Attributes[High(Attributes)];
  mLastIndex := High(Attributes);
  EndOffset := mLast.EndOffset;
  if not ReadChunks(Text, Lines, mLast.EndOffset, Lines.LineContentEnd(mLast.EndPos.Line), mChunks) or
    (Length(mChunks) > 1) or (mChunks <> nil) and ((mChunks[0].Others > 0) or (mChunks[0].Openers > 0) or
    (mChunks[0].Closers > ANeeded)) then
  begin
    Binding.CodeAfter := True;
    Exit;
  end;
  if mChunks <> nil then
  begin
    AddAfter(mLastIndex, mChunks[0], False);
    Dec(ANeeded, mChunks[0].Closers);
    EndOffset := mChunks[0].EndOffset;
  end;
  // Darunter nur Zeilen mit {$ENDIF}, die eine Bedingung um die Fälle schließen.
  mLine := Lines.PositionAt(EndOffset).Line + 1;
  while (ANeeded > 0) and (mLine < Lines.LineCount) and LineChunk(Text, Lines, mLine, mChunk) and
    (mChunk.Others = 0) and (mChunk.Openers = 0) and (mChunk.Closers > 0) and (mChunk.Closers <= ANeeded) do
  begin
    AddAfter(mLastIndex, mChunk, True);
    Dec(ANeeded, mChunk.Closers);
    EndOffset := mChunk.EndOffset;
    Inc(mLine);
  end;
end;

procedure TTriviaBinder.Check;
var
  mCount: TItemCount;
begin
  for mCount in Counts do
  begin
    if (mCount.Others > 0) or (mCount.CloseBefore > 0) or (mCount.OpenAfter > 0) or
      (mCount.OpenBefore <> mCount.CloseAfter) then
    begin
      Fail(TTriviaProblem.Directive);
    end;
  end;
end;

{ TTestCaseTrivia }

class function TTestCaseTrivia.Bind(const AText: string; const ALines: TLineTable;
  const AAttributes: TArray<TSyntaxNode>): TTriviaBinding;
var
  mBinder: TTriviaBinder;
  mIndex, mDeficit, mNet, mIncluded: Integer;
begin
  mBinder := Default(TTriviaBinder);
  mBinder.Text := AText;
  mBinder.Lines := ALines;
  mBinder.Attributes := AAttributes;
  SetLength(mBinder.Binding.Items, Length(AAttributes));
  SetLength(mBinder.Counts, Length(AAttributes));
  mBinder.ReadGaps;
  if mBinder.Binding.Problem = TTriviaProblem.None then
  begin
    for mIndex := 0 to High(AAttributes) - 1 do
    begin
      mBinder.AssignGap(mIndex);
    end;
  end;
  mBinder.Balance(mDeficit, mNet);
  mBinder.BindAbove(mDeficit, mIncluded);
  mBinder.BindBelow(mIncluded + mNet);
  mBinder.Check;
  mBinder.Binding.Range := TTextRange.Create(ALines.PositionAt(mBinder.StartOffset),
    ALines.PositionAt(mBinder.EndOffset));
  Result := mBinder.Binding;
end;

end.
