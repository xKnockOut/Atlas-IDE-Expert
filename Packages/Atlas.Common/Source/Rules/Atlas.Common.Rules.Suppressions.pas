unit Atlas.Common.Rules.Suppressions;

// Unterdrückung einzelner Stellen per Kommentar:
//   x := 1; // lsp-ignore: regel-a, regel-b   gilt für diese Zeile
//   // lsp-ignore: regel-a                    allein in der Zeile: gilt für die nächste Zeile
//   // lsp-ignore-file: regel-a                gilt für die ganze Datei
//   // lsp-ignore: regel-a -- Begründung       ab "--" folgt freier Text
// "*" steht für alle Regeln. Kommentare in { } und (* *) zählen ebenso.
// Merkt sich, welche Kommentare tatsächlich etwas unterdrückt haben, damit
// ungenutzte gemeldet werden können (#147). Jede Kennung hat ihre Stelle im
// Kommentar (IdRanges), damit die Engine unbekannte Kennungen genau markiert
// und mit Suggest einen Tippfehler-Vorschlag macht (#41).

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TSuppressionEntry = record
    /// <summary>Bereich des Kommentars.</summary>
    Range: TTextRange;
    /// <summary>Betroffene Zeile; -1 für die ganze Datei.</summary>
    TargetLine: Integer;
    /// <summary>Regelkennungen in Kleinbuchstaben, "*" für alle.</summary>
    Ids: TArray<string>;
    /// <summary>Stelle jeder Kennung (gleicher Index wie Ids); bei mehrzeiligen Kommentaren der Kommentar.</summary>
    IdRanges: TArray<TTextRange>;
    /// <summary>Der Kommentar steht allein in seiner Zeile.</summary>
    OwnLine: Boolean;
    Used: Boolean;
  end;

  TSuppressions = class
  private
    FEntries: TList<TSuppressionEntry>;
    class function Covers(const AIds: TArray<string>; const ARuleId: string): Boolean; static;
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    destructor Destroy; override;
    /// <summary>True, wenn ein Kommentar die Regel in ALine unterdrückt; markiert ihn als genutzt.</summary>
    function IsSuppressed(const ARuleId: string; ALine: Integer): Boolean;
    function Entries: TArray<TSuppressionEntry>;
    /// <summary>Kommentare, die bisher nichts unterdrückt haben.</summary>
    function UnusedEntries: TArray<TSuppressionEntry>;
    class function LineMarker: string; static;
    class function FileMarker: string; static;
    /// <summary>Ähnlichste Kennung aus AKnown für einen Tippfehler in AId; '' ohne passende.</summary>
    class function Suggest(const AId: string; const AKnown: TArray<string>): string; static;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract;

function CommentBody(const AText: string): string;
begin
  Result := AText;
  if StartsText('//', Result) then
  begin
    Result := Copy(Result, 3, MaxInt);
  end
  else if StartsText('{', Result) then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end
  else if StartsText('(*', Result) then
  begin
    Result := Copy(Result, 3, Length(Result) - 4);
  end;
  Result := Trim(Result);
end;

function SplitIds(const AText: string): TArray<string>;
var
  I, mStart: Integer;
  mList: TList<string>;
begin
  // Trenner: Komma, Leerzeichen, Tabulator.
  mList := TList<string>.Create;
  try
    mStart := 1;
    for I := 1 to Length(AText) + 1 do
    begin
      // Begründung nach "--" gehört nicht zu den Kennungen.
      if (I = mStart) and (Copy(AText, I, 2) = '--') then
      begin
        Break;
      end;
      if (I > Length(AText)) or CharInSet(AText[I], [',', ' ', #9]) then
      begin
        if I > mStart then
        begin
          mList.Add(LowerCase(Copy(AText, mStart, I - mStart)));
        end;
        mStart := I + 1;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Stellen der Kennungen AIds im Kommentar AToken, ab dem Marker gesucht.</summary>
function IdRangesOf(const AToken: TPascalToken; const AMarker: string; const AIds: TArray<string>): TArray<TTextRange>;
var
  mLower: string;
  mIndex, mFound, mCursor: Integer;
begin
  SetLength(Result, Length(AIds));
  mLower := LowerCase(AToken.Text);
  mCursor := Pos(AMarker, mLower) + Length(AMarker);
  for mIndex := 0 to High(AIds) do
  begin
    Result[mIndex] := TTextRange.Create(AToken.StartPos, AToken.EndPos);
    mFound := PosEx(AIds[mIndex], mLower, mCursor);
    if mFound = 0 then
    begin
      Continue;
    end;
    mCursor := mFound + Length(AIds[mIndex]);
    // Nur einzeilige Kommentare genau; sonst bleibt der ganze Kommentar.
    if (AToken.StartPos.Line = AToken.EndPos.Line) and (Pos(#10, Copy(AToken.Text, 1, mFound)) = 0) then
    begin
      Result[mIndex] := TTextRange.Create(AToken.StartPos.Line, AToken.StartPos.Character + mFound - 1,
        AToken.StartPos.Line, AToken.StartPos.Character + mFound - 1 + Length(AIds[mIndex]));
    end;
  end;
end;

/// <summary>Editierabstand nach Levenshtein, ohne Groß-/Kleinschreibung.</summary>
function Distance(const A, B: string): Integer;
var
  mPrevious, mCurrent: TArray<Integer>;
  I, J, mCost: Integer;
begin
  SetLength(mPrevious, Length(B) + 1);
  SetLength(mCurrent, Length(B) + 1);
  for J := 0 to Length(B) do
  begin
    mPrevious[J] := J;
  end;
  for I := 1 to Length(A) do
  begin
    mCurrent[0] := I;
    for J := 1 to Length(B) do
    begin
      mCost := 1;
      if UpCase(A[I]) = UpCase(B[J]) then
      begin
        mCost := 0;
      end;
      mCurrent[J] := Min(Min(mPrevious[J] + 1, mCurrent[J - 1] + 1), mPrevious[J - 1] + mCost);
    end;
    mPrevious := Copy(mCurrent);
  end;
  Result := mPrevious[Length(B)];
end;

{ TSuppressions }

class function TSuppressions.Suggest(const AId: string; const AKnown: TArray<string>): string;
var
  mKnown: string;
  mBest, mCurrent, mLimit: Integer;
begin
  Result := '';
  // Höchstens ein Viertel der Zeichen falsch, mindestens 1, höchstens 3.
  mLimit := Max(1, Min(3, Length(AId) div 4));
  mBest := mLimit + 1;
  for mKnown in AKnown do
  begin
    mCurrent := Distance(AId, mKnown);
    if mCurrent < mBest then
    begin
      mBest := mCurrent;
      Result := LowerCase(mKnown);
    end;
  end;
end;

class function TSuppressions.LineMarker: string;
begin
  Result := 'lsp-ignore:';
end;

class function TSuppressions.FileMarker: string;
begin
  Result := 'lsp-ignore-file:';
end;

constructor TSuppressions.Create(const ATokens: TArray<TPascalToken>);
var
  I, J: Integer;
  mBody, mLower: string;
  mEntry: TSuppressionEntry;
  mLastCodeLine: Integer;
  mCodeAfter: Boolean;
begin
  inherited Create;
  FEntries := TList<TSuppressionEntry>.Create;
  mLastCodeLine := -1;
  for I := 0 to High(ATokens) do
  begin
    if ATokens[I].Kind <> TPascalTokenKind.Comment then
    begin
      mLastCodeLine := ATokens[I].EndPos.Line;
      Continue;
    end;
    mBody := CommentBody(ATokens[I].Text);
    mLower := LowerCase(mBody);
    mEntry := Default(TSuppressionEntry);
    mEntry.Range := TTextRange.Create(ATokens[I].StartPos, ATokens[I].EndPos);
    if StartsText(FileMarker, mLower) then
    begin
      mEntry.Ids := SplitIds(Copy(mBody, Length(FileMarker) + 1, MaxInt));
      mEntry.IdRanges := IdRangesOf(ATokens[I], FileMarker, mEntry.Ids);
      mEntry.TargetLine := -1;
    end
    else if StartsText(LineMarker, mLower) then
    begin
      mEntry.Ids := SplitIds(Copy(mBody, Length(LineMarker) + 1, MaxInt));
      mEntry.IdRanges := IdRangesOf(ATokens[I], LineMarker, mEntry.Ids);
      if mLastCodeLine = ATokens[I].StartPos.Line then
      begin
        mEntry.TargetLine := ATokens[I].StartPos.Line;
      end
      else
      begin
        mEntry.TargetLine := ATokens[I].EndPos.Line + 1;
      end;
    end
    else
    begin
      Continue;
    end;
    mCodeAfter := False;
    J := I + 1;
    if (J <= High(ATokens)) and (ATokens[J].StartPos.Line = ATokens[I].EndPos.Line) then
    begin
      mCodeAfter := True;
    end;
    mEntry.OwnLine := (mLastCodeLine <> ATokens[I].StartPos.Line) and not mCodeAfter;
    FEntries.Add(mEntry);
  end;
end;

destructor TSuppressions.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TSuppressions.Covers(const AIds: TArray<string>; const ARuleId: string): Boolean;
var
  mId: string;
begin
  for mId in AIds do
  begin
    if (mId = '*') or SameText(TRuleIdAliases.Current(mId), TRuleIdAliases.Current(ARuleId)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSuppressions.IsSuppressed(const ARuleId: string; ALine: Integer): Boolean;
var
  I: Integer;
  mEntry: TSuppressionEntry;
begin
  Result := False;
  for I := 0 to FEntries.Count - 1 do
  begin
    mEntry := FEntries[I];
    if ((mEntry.TargetLine = -1) or (mEntry.TargetLine = ALine)) and Covers(mEntry.Ids, ARuleId) then
    begin
      mEntry.Used := True;
      FEntries[I] := mEntry;
      Result := True;
    end;
  end;
end;

function TSuppressions.Entries: TArray<TSuppressionEntry>;
begin
  Result := FEntries.ToArray;
end;

function TSuppressions.UnusedEntries: TArray<TSuppressionEntry>;
var
  mEntry: TSuppressionEntry;
begin
  Result := nil;
  for mEntry in FEntries do
  begin
    if not mEntry.Used then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

end.
