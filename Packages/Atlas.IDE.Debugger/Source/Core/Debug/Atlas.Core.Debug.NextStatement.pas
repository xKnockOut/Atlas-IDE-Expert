unit Atlas.Core.Debug.NextStatement;

// Ausführungspfeil ziehen bzw. „Nächste Anweisung hier“ (#871), Kern ohne IDE:
// - Check: Darf die nächste Anweisung von Zeile AFrom auf Zeile ATo (ab 0) gesetzt werden? Erlaubt sind nur Zeilen
//   mit ausführbarem Code (TAtlasRunTo.CodeLine) im selben innersten Rumpf einer Routine, im selben Teil derselben
//   try-Blöcke (nicht in einen try-, finally- oder except-Teil hinein oder heraus), nicht in den Rumpf einer
//   anonymen Methode hinein oder heraus und nicht in den Kopf einer for-Schleife mit Zähler (to/downto).
// - Effect: Welche Zeilen laufen erneut (Ziel davor) bzw. werden übersprungen (Ziel dahinter)?
// - FindAddress: Adresse der Zielzeile nahe beim Befehlszähler; die IDE beantwortet nur „welche Zeile hat diese
//   Adresse“, deshalb sucht Atlas von der aktuellen Adresse aus in beide Richtungen, bis die Adressen die Routine
//   verlassen, und nimmt die kleinste Adresse der Zielzeile (Beginn ihres ersten Codestücks).
// Die Blöcke liest eine Näherung über die Wörter des Textes (Kommentare und Zeichenketten übersprungen): begin,
// try, case (außer im Record), asm und record öffnen, end schließt; finally und except wechseln den Teil des
// innersten try.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.MethodToggle;

type
  {$SCOPEDENUMS ON}
  /// <summary>Ergebnis der Prüfung eines Ziels.</summary>
  TAtlasNextStatementVerdict = (Allowed, SameLine, OutsideRoutine, NoCode, OtherBlock, ForHead);
  /// <summary>Folge des Setzens: keine, Zeilen laufen erneut, Zeilen werden übersprungen.</summary>
  TAtlasNextStatementEffect = (None, Rerun, Skip);
  {$SCOPEDENUMS OFF}

  /// <summary>Zielzeile Line (ab 0) in FileName, gesucht zwischen den Adressen der Routine FirstLine..LastLine.
  /// </summary>
  TAtlasNextStatementTarget = record
    FileName: string;
    Line: Integer;
    FirstLine: Integer;
    LastLine: Integer;
  end;

  /// <summary>Zeile zu einer Adresse: False, wenn die IDE keine kennt; AFileName und ALine (ab 0) sonst.</summary>
  TAtlasLineAtAddress = reference to function(AAddress: UInt64; out AFileName: string; out ALine: Integer): Boolean;

  /// <summary>Ein Wort des Rumpfs, klein, mit Zeile (ab 0).</summary>
  TAtlasNextStatementWord = record
    Text: string;
    Line: Integer;
  end;

  TAtlasNextStatement = class
  public const
    /// <summary>So viele Adressen sucht FindAddress höchstens je Richtung.</summary>
    cMaxSearch = 65536;
  private
    FLines: TArray<string>;
    FPlaces: TArray<TAtlasMethodPlace>;
    /// <summary>Gelesener Rumpf: erste Zeile; -1 ohne.</summary>
    FFirst: Integer;
    /// <summary>Je Zeile des Rumpfs ab FFirst: Kennung der umgebenden try-Teile und anonymen Methoden.</summary>
    FBlocks: TArray<string>;
    /// <summary>Je Zeile des Rumpfs ab FFirst: Teil des Kopfs einer for-Schleife mit Zähler?</summary>
    FForHeads: TArray<Boolean>;
    procedure ReadBody(const APlace: TAtlasMethodPlace);
    procedure MarkForHead(const AWords: TArray<TAtlasNextStatementWord>; AIndex: Integer);
    function BlockOf(ALine: Integer): string;
    function IsForHead(ALine: Integer): Boolean;
  public
    /// <summary>Text der Datei mit dem Ausführungspunkt.</summary>
    constructor Create(const AText: string);
    /// <summary>Ziel ATo für den Ausführungspunkt in AFrom (Zeilen ab 0).</summary>
    function Check(AFrom, ATo: Integer): TAtlasNextStatementVerdict;
    /// <summary>Innerste Routine um ALine (ab 0): Zeilen AFirst..ALast samt Kopf; False außerhalb jeder.</summary>
    function RoutineAt(ALine: Integer; out AFirst, ALast: Integer): Boolean;
    /// <summary>Ab 0: Rerun = AFirst..ALast laufen erneut, Skip = AFirst..ALast werden übersprungen.</summary>
    class function Effect(AFrom, ATo: Integer; out AFirst, ALast: Integer): TAtlasNextStatementEffect; static;
    /// <summary>Kleinste Adresse der Zeile ATarget.Line zwischen den Adressen um AAddress, deren Zeilen in der
    /// Routine liegen. False, wenn keine gefunden.</summary>
    class function FindAddress(AAddress: UInt64; const ATarget: TAtlasNextStatementTarget;
      const ALineAt: TAtlasLineAtAddress; out AFound: UInt64): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Debug.RunTo;

type
  {$SCOPEDENUMS ON}
  TBlockKind = (Plain, TryBlock, Anonymous, RecordBlock);
  /// <summary>Wörter, die TBodyScan.Feed auswertet.</summary>
  TBlockWord = (ProcedureWord, FunctionWord, BeginWord, TryWord, RecordWord, CaseWord, AsmWord, FinallyWord,
    ExceptWord, EndWord);
  {$SCOPEDENUMS OFF}

  TBlock = record
    Kind: TBlockKind;
    Id: Integer;
    /// <summary>Bei try: 0 = try-Teil, 1 = finally- bzw. except-Teil.</summary>
    Part: Integer;
  end;

  /// <summary>Offene Blöcke beim Lesen eines Rumpfs, Wort für Wort.</summary>
  TBodyScan = record
    Stack: TArray<TBlock>;
    NextId: Integer;
    /// <summary>procedure bzw. function im Rumpf gelesen: Das nächste begin öffnet eine anonyme Methode.</summary>
    Anonymous: Boolean;
    procedure Push(AKind: TBlockKind; AId: Integer);
    function TopIs(AKind: TBlockKind): Boolean;
    /// <summary>Wort AWord lesen; True, wenn es den Teil des innersten try gewechselt hat.</summary>
    function Feed(const AWord: string): Boolean;
    /// <summary>Kennung der try-Teile und anonymen Methoden, von außen nach innen.</summary>
    function Key: string;
  end;

const
  /// <summary>So viele Wörter darf der Kopf einer for-Schleife bis do haben.</summary>
  cMaxForHeadWords = 64;
  cBlockWords: array[TBlockWord] of string = ('procedure', 'function', 'begin', 'try', 'record', 'case', 'asm', 'finally',
    'except', 'end');

/// <summary>Wörter der Zeilen ab AFirst mit ihrer Zeile.</summary>
function Flatten(const ALines: TArray<TArray<string>>; AFirst: Integer): TArray<TAtlasNextStatementWord>;
var
  mLine, mCount: Integer;
  mText: string;
begin
  mCount := 0;
  for mLine := 0 to High(ALines) do
  begin
    Inc(mCount, Length(ALines[mLine]));
  end;
  Result := nil;
  SetLength(Result, mCount);
  mCount := 0;
  for mLine := 0 to High(ALines) do
  begin
    for mText in ALines[mLine] do
    begin
      Result[mCount].Text := mText;
      Result[mCount].Line := AFirst + mLine;
      Inc(mCount);
    end;
  end;
end;

{ TBodyScan }

procedure TBodyScan.Push(AKind: TBlockKind; AId: Integer);
begin
  SetLength(Stack, Length(Stack) + 1);
  Stack[High(Stack)] := Default(TBlock);
  Stack[High(Stack)].Kind := AKind;
  Stack[High(Stack)].Id := AId;
end;

function TBodyScan.TopIs(AKind: TBlockKind): Boolean;
begin
  Result := (Length(Stack) > 0) and (Stack[High(Stack)].Kind = AKind);
end;

function TBodyScan.Feed(const AWord: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  mIndex := IndexStr(AWord, cBlockWords);
  if mIndex < 0 then
  begin
    Exit;
  end;
  case TBlockWord(mIndex) of
    TBlockWord.ProcedureWord, TBlockWord.FunctionWord:
      Anonymous := Length(Stack) > 0;
    TBlockWord.BeginWord:
      begin
        Inc(NextId);
        if Anonymous then
        begin
          Push(TBlockKind.Anonymous, NextId);
        end
        else
        begin
          Push(TBlockKind.Plain, NextId);
        end;
        Anonymous := False;
      end;
    TBlockWord.TryWord:
      begin
        Inc(NextId);
        Push(TBlockKind.TryBlock, NextId);
      end;
    TBlockWord.RecordWord:
      Push(TBlockKind.RecordBlock, 0);
    TBlockWord.CaseWord:
      // Der variante Teil eines Records (case … of) endet mit dem end des Records.
      if not TopIs(TBlockKind.RecordBlock) then
      begin
        Push(TBlockKind.Plain, 0);
      end;
    TBlockWord.AsmWord:
      Push(TBlockKind.Plain, 0);
    TBlockWord.FinallyWord, TBlockWord.ExceptWord:
      if TopIs(TBlockKind.TryBlock) then
      begin
        Stack[High(Stack)].Part := 1;
        Result := True;
      end;
    TBlockWord.EndWord:
      if Length(Stack) > 0 then
      begin
        SetLength(Stack, Length(Stack) - 1);
      end;
  end;
end;

function TBodyScan.Key: string;
var
  mBlock: TBlock;
begin
  Result := '';
  for mBlock in Stack do
  begin
    if mBlock.Kind = TBlockKind.TryBlock then
    begin
      Result := Result + 't' + IntToStr(mBlock.Id) + '.' + IntToStr(mBlock.Part) + ' ';
    end
    else if mBlock.Kind = TBlockKind.Anonymous then
    begin
      Result := Result + 'a' + IntToStr(mBlock.Id) + ' ';
    end;
  end;
end;

{ TAtlasNextStatement }

constructor TAtlasNextStatement.Create(const AText: string);
begin
  inherited Create;
  FLines := TAtlasLineAnchors.Lines(AText);
  FPlaces := TAtlasMethodToggle.Places(AText);
  FFirst := -1;
end;

procedure TAtlasNextStatement.MarkForHead(const AWords: TArray<TAtlasNextStatementWord>; AIndex: Integer);
var
  mEnd, mLine: Integer;
  mCounted: Boolean;
begin
  mCounted := False;
  mEnd := AIndex + 1;
  while (mEnd <= High(AWords)) and (mEnd - AIndex < cMaxForHeadWords) and (AWords[mEnd].Text <> 'do') do
  begin
    mCounted := mCounted or MatchStr(AWords[mEnd].Text, ['to', 'downto']);
    Inc(mEnd);
  end;
  if not mCounted or (mEnd > High(AWords)) then
  begin
    Exit;
  end;
  for mLine := AWords[AIndex].Line to AWords[mEnd].Line do
  begin
    FForHeads[mLine - FFirst] := True;
  end;
end;

procedure TAtlasNextStatement.ReadBody(const APlace: TAtlasMethodPlace);
var
  mWords: TArray<TAtlasNextStatementWord>;
  mScan: TBodyScan;
  mIndex, mLine, mDepth: Integer;

  // Eine Zeile gehört zum tiefsten Stand auf ihr: begin öffnet (Prolog), end schließt erst danach (Epilog).
  procedure Note;
  begin
    if Length(mScan.Stack) >= mDepth then
    begin
      mDepth := Length(mScan.Stack);
      FBlocks[mLine - FFirst] := mScan.Key;
    end;
  end;

  procedure NextLine;
  begin
    Inc(mLine);
    mDepth := -1;
    Note;
  end;

begin
  FFirst := APlace.FirstLine;
  FBlocks := nil;
  SetLength(FBlocks, APlace.LastLine - APlace.FirstLine + 1);
  FForHeads := nil;
  SetLength(FForHeads, Length(FBlocks));
  mWords := Flatten(TAtlasRunTo.CodeWords(FLines, APlace.FirstLine, APlace.LastLine), APlace.FirstLine);
  mScan := Default(TBodyScan);
  mLine := APlace.FirstLine;
  mDepth := -1;
  for mIndex := 0 to High(mWords) do
  begin
    // Zeilen ohne Wörter tragen den Stand davor.
    while mLine < mWords[mIndex].Line do
    begin
      NextLine;
    end;
    Note;
    // Die Zeile mit finally bzw. except gehört schon zum neuen Teil.
    if mScan.Feed(mWords[mIndex].Text) then
    begin
      mDepth := -1;
    end;
    if mWords[mIndex].Text = 'for' then
    begin
      MarkForHead(mWords, mIndex);
    end;
    Note;
  end;
  while mLine < APlace.LastLine do
  begin
    NextLine;
  end;
end;

function TAtlasNextStatement.BlockOf(ALine: Integer): string;
begin
  Result := FBlocks[ALine - FFirst];
end;

function TAtlasNextStatement.IsForHead(ALine: Integer): Boolean;
begin
  Result := FForHeads[ALine - FFirst];
end;

function TAtlasNextStatement.Check(AFrom, ATo: Integer): TAtlasNextStatementVerdict;
var
  mFromPlace, mToPlace: TAtlasMethodPlace;
begin
  if AFrom = ATo then
  begin
    Result := TAtlasNextStatementVerdict.SameLine;
  end
  else if not TAtlasMethodToggle.BodyAt(FPlaces, AFrom, mFromPlace) or
    not TAtlasMethodToggle.BodyAt(FPlaces, ATo, mToPlace) or (mFromPlace.FirstLine <> mToPlace.FirstLine) or
    (mFromPlace.LastLine <> mToPlace.LastLine) then
  begin
    Result := TAtlasNextStatementVerdict.OutsideRoutine;
  end
  else if not TAtlasRunTo.CodeLine(FLines, FPlaces, ATo) then
  begin
    Result := TAtlasNextStatementVerdict.NoCode;
  end
  else
  begin
    if FFirst <> mFromPlace.FirstLine then
    begin
      ReadBody(mFromPlace);
    end;
    Result := TAtlasNextStatementVerdict.Allowed;
    if IsForHead(ATo) then
    begin
      Result := TAtlasNextStatementVerdict.ForHead;
    end
    else if BlockOf(AFrom) <> BlockOf(ATo) then
    begin
      Result := TAtlasNextStatementVerdict.OtherBlock;
    end;
  end;
end;

function TAtlasNextStatement.RoutineAt(ALine: Integer; out AFirst, ALast: Integer): Boolean;
var
  mPlace: TAtlasMethodPlace;
begin
  AFirst := -1;
  ALast := -1;
  Result := TAtlasMethodToggle.BodyAt(FPlaces, ALine, mPlace);
  if Result then
  begin
    AFirst := mPlace.FirstLine;
    ALast := mPlace.LastLine;
  end;
end;

class function TAtlasNextStatement.Effect(AFrom, ATo: Integer; out AFirst, ALast: Integer): TAtlasNextStatementEffect;
begin
  AFirst := -1;
  ALast := -1;
  if ATo < AFrom then
  begin
    AFirst := ATo;
    ALast := AFrom - 1;
    Exit(TAtlasNextStatementEffect.Rerun);
  end;
  if ATo > AFrom then
  begin
    AFirst := AFrom;
    ALast := ATo - 1;
    Exit(TAtlasNextStatementEffect.Skip);
  end;
  Result := TAtlasNextStatementEffect.None;
end;

/// <summary>Gehört AAddress zur Routine von ATarget? ALine ist ihre Zeile.</summary>
function InRoutine(const ALineAt: TAtlasLineAtAddress; AAddress: UInt64; const ATarget: TAtlasNextStatementTarget;
  out ALine: Integer): Boolean;
var
  mFileName: string;
begin
  Result := ALineAt(AAddress, mFileName, ALine) and SameText(mFileName, ATarget.FileName) and
    (ALine >= ATarget.FirstLine) and (ALine <= ATarget.LastLine);
end;

class function TAtlasNextStatement.FindAddress(AAddress: UInt64; const ATarget: TAtlasNextStatementTarget;
  const ALineAt: TAtlasLineAtAddress; out AFound: UInt64): Boolean;
var
  mStep: Integer;
  mLine: Integer;
  mAddress: UInt64;
begin
  Result := False;
  AFound := 0;
  // Rückwärts bis zum Anfang der Routine: die kleinste Adresse der Zielzeile.
  mStep := 0;
  mAddress := AAddress;
  while (mStep < cMaxSearch) and (mAddress > 0) and InRoutine(ALineAt, mAddress, ATarget, mLine) do
  begin
    if mLine = ATarget.Line then
    begin
      AFound := mAddress;
      Result := True;
    end;
    Dec(mAddress);
    Inc(mStep);
  end;
  // Sonst vorwärts: die erste Adresse der Zielzeile.
  mStep := 0;
  mAddress := AAddress + 1;
  while not Result and (mStep < cMaxSearch) and InRoutine(ALineAt, mAddress, ATarget, mLine) do
  begin
    if mLine = ATarget.Line then
    begin
      AFound := mAddress;
      Result := True;
    end;
    Inc(mAddress);
    Inc(mStep);
  end;
end;

end.
