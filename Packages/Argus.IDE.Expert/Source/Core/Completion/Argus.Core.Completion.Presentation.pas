unit Argus.Core.Completion.Presentation;

// Darstellung eines Eintrags in der Liste (#420, #421), ohne Fenster:
//   - Badge: Kürzel und Farbart nach der Art; Funktion oder Prozedur nach
//     der Signatur, solange der Server beides als Methode meldet.
//   - Detail: gedämpfter Text rechts (Typ, Klasse, Unit-Datei).
//   - Tags: "+ Unit" für Einträge aus nicht eingebundenen Units (#180),
//     "deprecated", "constructor"/"destructor", "+2" bei drei Überladungen
//     (#425), "Helper" (#456), "zuletzt"/"häufig" (#418).
//   - Geerbte Member (#419): Detail beginnt mit der deklarierenden Klasse.
//   - Treffer: Positionen der getippten Zeichen im Namen zum Hervorheben,
//     nach denselben Regeln wie TArgusCompletionMatcher.

interface

uses
  System.SysUtils,
  Argus.Core.Completion.Contract,
  Argus.Core.Style.Palette;

type
  TArgusBadge = record
    Kind: TArgusBadgeKind;
    /// <summary>Zwei Buchstaben, z. B. "fn".</summary>
    Code: string;
  end;

  TArgusTagKind = (Neutral, Accent, Add, Warn);

  /// <summary>Übersetzbare Marken (#446); Plain = Text unverändert zeigen.</summary>
  TArgusTagId = (Plain, Recent, Frequent);

  TArgusTag = record
    Text: string;
    Kind: TArgusTagKind;
    Id: TArgusTagId;
  end;

  TArgusTags = TArray<TArgusTag>;

  TArgusItemPresentation = class
  public
    class function Badge(const AItem: TArgusCompletionItem): TArgusBadge; static;
    class function Detail(const AItem: TArgusCompletionItem): string; static;
    class function Tags(const AItem: TArgusCompletionItem): TArgusTags; static;
    /// <summary>Unit, die beim Übernehmen in uses ergänzt wird; '' wenn eingebunden.</summary>
    class function MissingUnit(const AItem: TArgusCompletionItem): string; static;
    /// <summary>1-basierte Positionen in AName, die APattern trifft; leer ohne Treffer.</summary>
    class function Highlights(const APattern, AName: string): TArray<Integer>; static;
  end;

implementation

uses
  System.Character,
  System.StrUtils,
  Argus.Core.Completion.Matching;

const
  UsesSuffix = ' (uses ergänzen)';

function MakeBadge(AKind: TArgusBadgeKind; const ACode: string): TArgusBadge;
begin
  Result.Kind := AKind;
  Result.Code := ACode;
end;

function MakeTag(const AText: string; AKind: TArgusTagKind): TArgusTag;
begin
  Result.Text := AText;
  Result.Kind := AKind;
  Result.Id := TArgusTagId.Plain;
end;

function IsWordStart(const AName: string; AIndex: Integer): Boolean;
begin
  Result := TArgusCompletionMatcher.IsWordStart(AName, AIndex);
end;

function SameChar(A, B: Char): Boolean;
begin
  Result := UpCase(A) = UpCase(B);
end;

function Range(AStart, ACount: Integer): TArray<Integer>;
var
  Index: Integer;
begin
  SetLength(Result, ACount);
  for Index := 0 to ACount - 1 do
    Result[Index] := AStart + Index;
end;

function WordStartPositions(const APattern, AName: string): TArray<Integer>;
var
  PatternIndex, NameIndex: Integer;
begin
  Result := nil;
  PatternIndex := 1;
  for NameIndex := 1 to Length(AName) do
    if (PatternIndex <= Length(APattern)) and IsWordStart(AName, NameIndex) and
      SameChar(AName[NameIndex], APattern[PatternIndex]) then
    begin
      Result := Result + [NameIndex];
      Inc(PatternIndex);
    end;
  if PatternIndex <= Length(APattern) then
    Result := nil;
end;

function SubsequencePositions(const APattern, AName: string): TArray<Integer>;
var
  Reached: TArray<TArray<Boolean>>;
  PatternIndex, NameIndex, Previous: Integer;
  Before: Boolean;
begin
  // Wie MatchesSubsequence, aber mit allen Zwischenständen, um den Weg zurückzuverfolgen.
  Result := nil;
  SetLength(Reached, Length(APattern) + 1, Length(AName) + 1);
  for NameIndex := 1 to Length(AName) do
    Reached[1][NameIndex] := IsWordStart(AName, NameIndex) and SameChar(AName[NameIndex], APattern[1]);
  for PatternIndex := 2 to Length(APattern) do
  begin
    Before := False;
    for NameIndex := 1 to Length(AName) do
    begin
      Reached[PatternIndex][NameIndex] := SameChar(AName[NameIndex], APattern[PatternIndex]) and
        (Reached[PatternIndex - 1][NameIndex - 1] or (Before and IsWordStart(AName, NameIndex)));
      Before := Before or Reached[PatternIndex - 1][NameIndex - 1];
    end;
  end;
  // Frühestes Ende des ganzen Musters, dann rückwärts: bevorzugt direkt davor.
  NameIndex := 0;
  for Previous := 1 to Length(AName) do
    if Reached[Length(APattern)][Previous] then
    begin
      NameIndex := Previous;
      Break;
    end;
  if NameIndex = 0 then
    Exit;
  SetLength(Result, Length(APattern));
  for PatternIndex := Length(APattern) downto 1 do
  begin
    Result[PatternIndex - 1] := NameIndex;
    if PatternIndex = 1 then
      Break;
    if Reached[PatternIndex - 1][NameIndex - 1] then
      Dec(NameIndex)
    else
    begin
      Previous := NameIndex - 2;
      while (Previous >= 1) and not Reached[PatternIndex - 1][Previous] do
        Dec(Previous);
      NameIndex := Previous;
    end;
  end;
end;

{ TArgusItemPresentation }

class function TArgusItemPresentation.Badge(const AItem: TArgusCompletionItem): TArgusBadge;
var
  Signature: string;
begin
  Signature := LowerCase(TrimLeft(AItem.Signature));
  case AItem.Kind of
    TArgusItemKind.Procedure_, TArgusItemKind.Destructor_:
      Result := MakeBadge(TArgusBadgeKind.Procedure_, 'pr');
    TArgusItemKind.Function_, TArgusItemKind.Constructor_:
      Result := MakeBadge(TArgusBadgeKind.Function_, 'fn');
    TArgusItemKind.Method:
      if Signature.StartsWith('procedure') or Signature.StartsWith('destructor') then
        Result := MakeBadge(TArgusBadgeKind.Procedure_, 'pr')
      else
        Result := MakeBadge(TArgusBadgeKind.Function_, 'fn');
    TArgusItemKind.Property_:
      Result := MakeBadge(TArgusBadgeKind.Property_, 'pp');
    TArgusItemKind.Field:
      Result := MakeBadge(TArgusBadgeKind.Field, 'fd');
    TArgusItemKind.Event:
      Result := MakeBadge(TArgusBadgeKind.Event, 'ev');
    TArgusItemKind.Constant, TArgusItemKind.EnumMember:
      Result := MakeBadge(TArgusBadgeKind.Constant, 'co');
    TArgusItemKind.Type_, TArgusItemKind.Class_, TArgusItemKind.Interface_, TArgusItemKind.Record_,
    TArgusItemKind.Enum:
      Result := MakeBadge(TArgusBadgeKind.Type_, 'ty');
    TArgusItemKind.Variable, TArgusItemKind.Parameter:
      Result := MakeBadge(TArgusBadgeKind.Variable, 'va');
    TArgusItemKind.Unit_:
      Result := MakeBadge(TArgusBadgeKind.Unit_, 'un');
    TArgusItemKind.Keyword:
      Result := MakeBadge(TArgusBadgeKind.Keyword, 'kw');
    TArgusItemKind.Snippet:
      Result := MakeBadge(TArgusBadgeKind.Snippet, 'sn');
  else
    Result := MakeBadge(TArgusBadgeKind.Variable, '··');
  end;
end;

class function TArgusItemPresentation.MissingUnit(const AItem: TArgusCompletionItem): string;
var
  Edit: TArgusTextEdit;
  Text: string;
begin
  Result := '';
  if AItem.UnitUsed then
    Exit;
  // Der Server nennt die Unit im Detail ("System.Classes (uses ergänzen)").
  if EndsText(UsesSuffix, AItem.Signature) then
    Exit(Copy(AItem.Signature, 1, Length(AItem.Signature) - Length(UsesSuffix)));
  // Sonst aus der Ergänzung selbst (", System.Classes" bzw. "uses System.Classes;").
  for Edit in AItem.AdditionalEdits do
  begin
    Text := Trim(Edit.NewText.Replace(',', ' ').Replace(';', ' '));
    if StartsText('uses', Text) and ((Length(Text) = 4) or not Text[5].IsLetter) then
      Text := Trim(Copy(Text, 5, MaxInt));
    if Text <> '' then
      Exit(Text);
  end;
end;

class function TArgusItemPresentation.Detail(const AItem: TArgusCompletionItem): string;
begin
  if MissingUnit(AItem) <> '' then
    Exit('');
  Result := AItem.Signature;
  // Units: nur der Dateiname statt des ganzen Pfads.
  if AItem.Kind = TArgusItemKind.Unit_ then
    Result := ExtractFileName(Result);
  // Geerbt (#419): Herkunft vorn, damit sie beim Kürzen bleibt.
  if (AItem.Depth > 0) and (AItem.DeclaringClass <> '') then
    if (Result <> '') and not SameText(Result, AItem.DeclaringClass) then
      Result := AItem.DeclaringClass + ' · ' + Result
    else
      Result := AItem.DeclaringClass;
end;

class function TArgusItemPresentation.Tags(const AItem: TArgusCompletionItem): TArgusTags;
var
  Directive, MissingName: string;
begin
  Result := nil;
  MissingName := MissingUnit(AItem);
  if MissingName <> '' then
    Result := Result + [MakeTag('+ ' + MissingName, TArgusTagKind.Add)];
  case AItem.Kind of
    TArgusItemKind.Constructor_: Result := Result + [MakeTag('constructor', TArgusTagKind.Neutral)];
    TArgusItemKind.Destructor_: Result := Result + [MakeTag('destructor', TArgusTagKind.Neutral)];
  end;
  for Directive in AItem.Directives do
    if SameText(Directive, 'deprecated') then
      Result := Result + [MakeTag('deprecated', TArgusTagKind.Warn)];
  if AItem.OverloadCount > 1 then
    Result := Result + [MakeTag('+' + IntToStr(AItem.OverloadCount - 1), TArgusTagKind.Neutral)];
  if AItem.IsHelper then
    Result := Result + [MakeTag('Helper', TArgusTagKind.Accent)];
  case AItem.Usage of
    TArgusUsageMark.Recent:
      begin
        Result := Result + [MakeTag('zuletzt', TArgusTagKind.Accent)];
        Result[High(Result)].Id := TArgusTagId.Recent;
      end;
    TArgusUsageMark.Frequent:
      begin
        Result := Result + [MakeTag('häufig', TArgusTagKind.Neutral)];
        Result[High(Result)].Id := TArgusTagId.Frequent;
      end;
  end;
end;

class function TArgusItemPresentation.Highlights(const APattern, AName: string): TArray<Integer>;
var
  Score, Found: Integer;
begin
  Result := nil;
  Score := TArgusCompletionMatcher.Score(APattern, AName);
  if (APattern = '') or (Score = TArgusCompletionMatcher.NoMatch) then
    Exit;
  if Score >= TArgusCompletionMatcher.ScorePrefix then
    Exit(Range(1, Length(APattern)));
  if Score = TArgusCompletionMatcher.ScoreWordStarts then
    Exit(WordStartPositions(APattern, AName));
  if Score = TArgusCompletionMatcher.ScoreSubstring then
  begin
    Found := Pos(APattern.ToUpper, AName.ToUpper);
    Exit(Range(Found, Length(APattern)));
  end;
  Result := SubsequencePositions(APattern, AName);
end;

end.
