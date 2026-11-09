unit Atlas.Core.Outline.Statements;

// Rahmen im Rumpf einer Routine für die Brotkrumenleiste (#1769), Kern ohne
// VCL und OTA:
// - Nur try/except/finally und case mit seinen Zweigen, kein if, for, while
//   oder with. Grundlage sind die Wörter der Routine ohne lokale Routinen und
//   Typen (TAtlasTypeText.RoutineTokens); Kommentare und Strings fallen weg.
// - begin, asm, try und case öffnen einen Rahmen, end schließt ihn. Im
//   case steht vor dem Doppelpunkt eine Marke; ein Semikolon auf der Ebene
//   des case beginnt die nächste. else gehört zum case, wenn auf seiner Ebene
//   kein if offen ist.
// - At liefert die Rahmen um die Stelle, außen zuerst: Teil des try-Blocks
//   bzw. case-Kopf und Zweig, jeweils mit den Teilen bzw. Zweigen als
//   Sprungziele.

interface

uses
  Atlas.Core.Outline.Model;

type
  /// <summary>Teil eines Rahmens als Sprungziel (try, except, finally, Marke eines Zweigs, else).</summary>
  TAtlasStatementPart = record
    Text: string;
    /// <summary>Anfang, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
  end;

  TAtlasStatementParts = TArray<TAtlasStatementPart>;

  /// <summary>Glied für einen Rahmen um die Stelle.</summary>
  TAtlasStatementFrame = record
    /// <summary>„try“, „except“, „finally“, „case Art of“ bzw. die Marke des Zweigs.</summary>
    Text: string;
    /// <summary>Sprungziele: Teile des try-Blocks bzw. Zweige des case.</summary>
    Parts: TAtlasStatementParts;
    /// <summary>Index des aktuellen Teils in Parts; -1 ohne (case-Kopf).</summary>
    Current: Integer;
  end;

  TAtlasStatementFrames = TArray<TAtlasStatementFrame>;

  TAtlasStatementFinder = class
  public
    /// <summary>Rahmen um ALine/ACharacter (0-basiert) im Rumpf der innersten Routine dort, außen zuerst.
    /// </summary>
    class function At(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ALine,
      ACharacter: Integer): TAtlasStatementFrames; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Outline.TypeText;

const
  /// <summary>Längster Text eines Glieds (Marke, case-Ausdruck); danach „…“.</summary>
  cMaxText = 40;

type
{$SCOPEDENUMS ON}
  TFrameKind = (Block, Try_, Case_);
  /// <summary>Stand im case: vor dem Doppelpunkt (Marke), in der Anweisung, im else-Teil.</summary>
  TCaseState = (Head, Label_, Statement, Else_);
{$SCOPEDENUMS OFF}

  /// <summary>Rahmen beim Lauf über die Wörter.</summary>
  TFrame = record
    Kind: TFrameKind;
    State: TCaseState;
    /// <summary>Offene if auf dieser Ebene (für else).</summary>
    PendingIf: Integer;
    /// <summary>Ende des letzten Trenners (of bzw. ;): Anfang der nächsten Marke.</summary>
    SeparatorLine: Integer;
    SeparatorCharacter: Integer;
    /// <summary>case-Kopf („case Art of“).</summary>
    Head: TAtlasStatementPart;
    Parts: TAtlasStatementParts;
    /// <summary>Wort end, 0-basiert; ohne end das Ende der Routine.</summary>
    EndLine: Integer;
    EndCharacter: Integer;
  end;

  /// <summary>Sammelt alle try- und case-Rahmen einer Routine.</summary>
  TFrameCollector = class
  private
    FLines: TArray<string>;
    FTokens: TAtlasTypeTokens;
    FStack: TArray<TFrame>;
    FDone: TArray<TFrame>;
    function Top: Integer;
    procedure Push(AKind: TFrameKind; const AToken: TAtlasTypeToken);
    procedure Pop(const AToken: TAtlasTypeToken);
    procedure AddPart(const AText: string; ALine, ACharacter: Integer);
    procedure CaseHead(AIndex: Integer);
    procedure CaseLabel(const AToken: TAtlasTypeToken);
    procedure Semicolon(const AToken: TAtlasTypeToken);
    procedure ElseWord(const AToken: TAtlasTypeToken);
    procedure Word(AIndex: Integer);
  public
    constructor Create(const ALines: TArray<string>; const ATokens: TAtlasTypeTokens);
    function Run(AEndLine, AEndCharacter: Integer): TArray<TFrame>;
  end;

function Shortened(const AText: string): string;
begin
  Result := AText;
  if Length(Result) > cMaxText then
  begin
    Result := Copy(Result, 1, cMaxText) + '…';
  end;
end;

/// <summary>Quelltext von ALine/ACharacter bis vor AEndLine/AEndCharacter, Leerraum zusammengefasst.</summary>
function TextBetween(const ALines: TArray<string>; ALine, ACharacter, AEndLine, AEndCharacter: Integer): string;
var
  mLine: Integer;
  mPart: string;
begin
  Result := '';
  for mLine := ALine to AEndLine do
  begin
    if (mLine < 0) or (mLine > High(ALines)) then
    begin
      Continue;
    end;
    mPart := ALines[mLine];
    if mLine = AEndLine then
    begin
      mPart := Copy(mPart, 1, AEndCharacter);
    end;
    if mLine = ALine then
    begin
      mPart := Copy(mPart, ACharacter + 1, MaxInt);
    end;
    Result := Result + ' ' + Trim(mPart);
  end;
  Result := Trim(Result);
  while Pos('  ', Result) > 0 do
  begin
    Result := Result.Replace('  ', ' ');
  end;
end;

/// <summary>Erstes Zeichen ab ALine/ACharacter, das kein Leerraum ist.</summary>
procedure SkipBlanks(const ALines: TArray<string>; var ALine, ACharacter: Integer);
begin
  while ALine <= High(ALines) do
  begin
    while (ACharacter < Length(ALines[ALine])) and (ALines[ALine][ACharacter + 1] <= ' ') do
    begin
      Inc(ACharacter);
    end;
    if ACharacter < Length(ALines[ALine]) then
    begin
      Exit;
    end;
    Inc(ALine);
    ACharacter := 0;
  end;
end;

constructor TFrameCollector.Create(const ALines: TArray<string>; const ATokens: TAtlasTypeTokens);
begin
  inherited Create;
  FLines := ALines;
  FTokens := ATokens;
end;

function TFrameCollector.Top: Integer;
begin
  Result := High(FStack);
end;

procedure TFrameCollector.Push(AKind: TFrameKind; const AToken: TAtlasTypeToken);
var
  mFrame: TFrame;
begin
  mFrame := Default(TFrame);
  mFrame.Kind := AKind;
  mFrame.State := TCaseState.Head;
  FStack := FStack + [mFrame];
  if AKind = TFrameKind.Try_ then
  begin
    AddPart('try', AToken.Line, AToken.Character);
  end
  else if AKind = TFrameKind.Case_ then
  begin
    FStack[Top].Head.Line := AToken.Line;
    FStack[Top].Head.Character := AToken.Character;
  end;
end;

procedure TFrameCollector.Pop(const AToken: TAtlasTypeToken);
begin
  if Top < 0 then
  begin
    Exit;
  end;
  FStack[Top].EndLine := AToken.Line;
  FStack[Top].EndCharacter := AToken.Character;
  if FStack[Top].Kind <> TFrameKind.Block then
  begin
    FDone := FDone + [FStack[Top]];
  end;
  SetLength(FStack, Length(FStack) - 1);
end;

procedure TFrameCollector.AddPart(const AText: string; ALine, ACharacter: Integer);
var
  mPart: TAtlasStatementPart;
begin
  mPart.Text := AText;
  mPart.Line := ALine;
  mPart.Character := ACharacter;
  FStack[Top].Parts := FStack[Top].Parts + [mPart];
end;

/// <summary>of des case an AIndex: Kopf „case … of“, danach die erste Marke.</summary>
procedure TFrameCollector.CaseHead(AIndex: Integer);
var
  mToken: TAtlasTypeToken;
begin
  mToken := FTokens[AIndex];
  FStack[Top].Head.Text := 'case ' + Shortened(TextBetween(FLines, FStack[Top].Head.Line,
    FStack[Top].Head.Character + 4, mToken.Line, mToken.Character)) + ' of';
  FStack[Top].State := TCaseState.Label_;
  FStack[Top].SeparatorLine := mToken.Line;
  FStack[Top].SeparatorCharacter := mToken.Character + 2;
end;

/// <summary>Doppelpunkt am Ende einer Marke: Zweig von hinter dem Trenner bis vor AToken.</summary>
procedure TFrameCollector.CaseLabel(const AToken: TAtlasTypeToken);
var
  mLine, mCharacter: Integer;
begin
  mLine := FStack[Top].SeparatorLine;
  mCharacter := FStack[Top].SeparatorCharacter;
  SkipBlanks(FLines, mLine, mCharacter);
  AddPart(Shortened(TextBetween(FLines, mLine, mCharacter, AToken.Line, AToken.Character)), mLine, mCharacter);
  FStack[Top].State := TCaseState.Statement;
  FStack[Top].PendingIf := 0;
end;

procedure TFrameCollector.Semicolon(const AToken: TAtlasTypeToken);
begin
  FStack[Top].PendingIf := 0;
  if (FStack[Top].Kind = TFrameKind.Case_) and (FStack[Top].State = TCaseState.Statement) then
  begin
    FStack[Top].State := TCaseState.Label_;
    FStack[Top].SeparatorLine := AToken.Line;
    FStack[Top].SeparatorCharacter := AToken.Character + 1;
  end;
end;

procedure TFrameCollector.ElseWord(const AToken: TAtlasTypeToken);
begin
  if FStack[Top].PendingIf > 0 then
  begin
    Dec(FStack[Top].PendingIf);
  end
  else if (FStack[Top].Kind = TFrameKind.Case_) and (FStack[Top].State in [TCaseState.Label_,
    TCaseState.Statement]) then
  begin
    AddPart('else', AToken.Line, AToken.Character);
    FStack[Top].State := TCaseState.Else_;
  end;
end;

procedure TFrameCollector.Word(AIndex: Integer);
var
  mToken: TAtlasTypeToken;
begin
  mToken := FTokens[AIndex];
  if TAtlasTypeText.IsOneOf(mToken.Text, ['begin', 'asm']) then
  begin
    Push(TFrameKind.Block, mToken);
  end
  else if mToken.Text = 'try' then
  begin
    Push(TFrameKind.Try_, mToken);
  end
  else if mToken.Text = 'case' then
  begin
    Push(TFrameKind.Case_, mToken);
  end
  else if Top < 0 then
  begin
    Exit;
  end
  else if mToken.Text = 'end' then
  begin
    Pop(mToken);
  end
  else if TAtlasTypeText.IsOneOf(mToken.Text, ['except', 'finally']) and (FStack[Top].Kind = TFrameKind.Try_) then
  begin
    AddPart(mToken.Text, mToken.Line, mToken.Character);
  end
  else if (mToken.Text = 'of') and (FStack[Top].Kind = TFrameKind.Case_) and
    (FStack[Top].State = TCaseState.Head) then
  begin
    CaseHead(AIndex);
  end
  else if mToken.Text = 'if' then
  begin
    Inc(FStack[Top].PendingIf);
  end
  else if mToken.Text = 'else' then
  begin
    ElseWord(mToken);
  end;
end;

function TFrameCollector.Run(AEndLine, AEndCharacter: Integer): TArray<TFrame>;
var
  mIndex, mDepth: Integer;
  mToken, mEnd: TAtlasTypeToken;
begin
  FStack := nil;
  FDone := nil;
  mDepth := 0;
  for mIndex := 0 to High(FTokens) do
  begin
    mToken := FTokens[mIndex];
    if (mToken.Text = '(') or (mToken.Text = '[') then
    begin
      Inc(mDepth);
    end
    else if (mToken.Text = ')') or (mToken.Text = ']') then
    begin
      Dec(mDepth);
    end
    else if mToken.Word and not mToken.Escaped then
    begin
      Word(mIndex);
    end
    else if (mDepth <= 0) and (Top >= 0) and (mToken.Text = ';') then
    begin
      Semicolon(mToken);
    end
    else if (mDepth <= 0) and (Top >= 0) and (mToken.Text = ':') and (FStack[Top].Kind = TFrameKind.Case_) and
      (FStack[Top].State = TCaseState.Label_) then
    begin
      CaseLabel(mToken);
    end;
  end;
  // Ohne end: bis zum Ende der Routine.
  mEnd := Default(TAtlasTypeToken);
  mEnd.Line := AEndLine;
  mEnd.Character := AEndCharacter;
  while Top >= 0 do
  begin
    Pop(mEnd);
  end;
  Result := FDone;
end;

/// <summary>Anfang des Rahmens: try bzw. case.</summary>
function StartOf(const AFrame: TFrame): TAtlasStatementPart;
begin
  if AFrame.Kind = TFrameKind.Try_ then
  begin
    Result := AFrame.Parts[0];
  end
  else
  begin
    Result := AFrame.Head;
  end;
end;

/// <summary>Rahmen schließen nach ihren inneren; nach Anfang geordnet stehen äußere vorn.</summary>
procedure SortByStart(var AFrames: TArray<TFrame>);
var
  mIndex, mOther: Integer;
  mFrame: TFrame;
  mStart, mOtherStart: TAtlasStatementPart;
begin
  for mIndex := 1 to High(AFrames) do
  begin
    mFrame := AFrames[mIndex];
    mStart := StartOf(mFrame);
    mOther := mIndex - 1;
    while mOther >= 0 do
    begin
      mOtherStart := StartOf(AFrames[mOther]);
      if not TAtlasTypeText.Before(mStart.Line, mStart.Character, mOtherStart.Line, mOtherStart.Character) then
      begin
        Break;
      end;
      AFrames[mOther + 1] := AFrames[mOther];
      Dec(mOther);
    end;
    AFrames[mOther + 1] := mFrame;
  end;
end;

/// <summary>Innerste Routine (Rumpf) an der Stelle; -1 ohne.</summary>
function RoutineAt(const ANodes: TAtlasOutlineNodes; ALine, ACharacter: Integer): Integer;
var
  mIndex: Integer;
  mNode: TAtlasOutlineNode;
begin
  Result := -1;
  for mIndex := 0 to High(ANodes) do
  begin
    mNode := ANodes[mIndex];
    if (mNode.Category in [TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine]) and
      not TAtlasTypeText.Before(ALine, ACharacter, mNode.StartLine, mNode.StartCharacter) and
      TAtlasTypeText.Before(ALine, ACharacter, mNode.EndLine, mNode.EndCharacter) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Letzter Teil, der vor der Stelle beginnt; -1 ohne.</summary>
function PartAt(const AParts: TAtlasStatementParts; ALine, ACharacter: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AParts) do
  begin
    if not TAtlasTypeText.Before(ALine, ACharacter, AParts[mIndex].Line, AParts[mIndex].Character) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Glieder eines Rahmens an der Stelle: Teil des try-Blocks bzw. case-Kopf und Zweig.</summary>
function FrameItems(const AFrame: TFrame; ALine, ACharacter: Integer): TAtlasStatementFrames;
var
  mItem: TAtlasStatementFrame;
begin
  Result := nil;
  mItem.Parts := AFrame.Parts;
  mItem.Current := PartAt(AFrame.Parts, ALine, ACharacter);
  if AFrame.Kind = TFrameKind.Try_ then
  begin
    mItem.Text := AFrame.Parts[mItem.Current].Text;
    Result := [mItem];
    Exit;
  end;
  mItem.Text := AFrame.Head.Text;
  if mItem.Text = '' then
  begin
    mItem.Text := 'case';
  end;
  mItem.Current := -1;
  Result := [mItem];
  mItem.Current := PartAt(AFrame.Parts, ALine, ACharacter);
  if mItem.Current >= 0 then
  begin
    mItem.Text := AFrame.Parts[mItem.Current].Text;
    Result := Result + [mItem];
  end;
end;

class function TAtlasStatementFinder.At(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ALine,
  ACharacter: Integer): TAtlasStatementFrames;
var
  mRoutine: Integer;
  mCollector: TFrameCollector;
  mFrames: TArray<TFrame>;
  mFrame: TFrame;
  mStart: TAtlasStatementPart;
begin
  Result := nil;
  mRoutine := RoutineAt(ANodes, ALine, ACharacter);
  if mRoutine < 0 then
  begin
    Exit;
  end;
  mCollector := TFrameCollector.Create(ALines, TAtlasTypeText.RoutineTokens(ANodes, ALines, mRoutine));
  try
    mFrames := mCollector.Run(ANodes[mRoutine].EndLine, ANodes[mRoutine].EndCharacter);
  finally
    mCollector.Free;
  end;
  SortByStart(mFrames);
  for mFrame in mFrames do
  begin
    mStart := StartOf(mFrame);
    if not TAtlasTypeText.Before(ALine, ACharacter, mStart.Line, mStart.Character) and
      TAtlasTypeText.Before(ALine, ACharacter, mFrame.EndLine, mFrame.EndCharacter) then
    begin
      Result := Result + FrameItems(mFrame, ALine, ACharacter);
    end;
  end;
end;

end.
