unit Atlas.Core.Designer.FormTexts;

// Alle Texte des Formulars als Tabelle (#728), ohne VCL und Windows: Hinweise
// zu den Texten, die das Plugin aus den Komponenten liest.
// - Tastenkürzel: dasselbe „&“-Zeichen zweimal in derselben Gruppe (Parent
//   bzw. Menüebene); Einträge ohne Gruppe werden nicht verglichen.
// - Schreibweisen: dasselbe Wort ohne Bindestriche und ohne Groß-/Klein-
//   schreibung, aber anders geschrieben („E-Mail“/„Email“/„eMail“), dazu
//   eigene Synonymgruppen („Lieferant, Lieferer; Kunde, Abnehmer“). Der erste
//   Buchstabe zählt nicht, damit Satzanfänge kein Hinweis sind.
// - Abgeschnitten: misst das Plugin (Textbreite mit der Schrift), hier nur
//   übernommen. Leerzeichen am Anfang/Ende oder doppelt. Doppelpunkt fehlt bei
//   Labels vor einem Eingabefeld.

interface

type
{$SCOPEDENUMS ON}
  TAtlasTextCheck = (Accelerators, Variants, Truncated, Whitespace, LabelColon);
{$SCOPEDENUMS OFF}
  TAtlasTextChecks = set of TAtlasTextCheck;

  TAtlasTextFinding = record
    Check: TAtlasTextCheck;
    /// <summary>Bei Tastenkürzeln der Buchstabe und die andere Komponente, bei Schreibweisen die anderen.</summary>
    Detail: string;
  end;

  TAtlasTextEntry = record
    Component: string;
    ClassName: string;
    /// <summary>Eigenschaft als Pfad: Caption, EditLabel.Caption, Columns[2].Title.Caption, Items[3].</summary>
    Path: string;
    Text: string;
    /// <summary>Gruppe für Tastenkürzel (Parent, Menüebene); leer ohne Prüfung.</summary>
    Group: string;
    /// <summary>Label vor einem Eingabefeld (FocusControl).</summary>
    NeedsColon: Boolean;
    /// <summary>Vom Plugin gemessen: Text breiter als der Platz.</summary>
    Truncated: Boolean;
    Findings: TArray<TAtlasTextFinding>;
    class function Create(const AComponent, AClassName, APath, AText, AGroup: string): TAtlasTextEntry; static;
    function HasFindings: Boolean;
  end;

  TAtlasFormTexts = class
  public const
    cDefaultChecks = 'accelerators, variants, truncated, whitespace';
    cDefaultExcluded = 'SQL, CommandText';
  public
    /// <summary>„accelerators, variants, truncated, whitespace, labelColon“; Unbekanntes wird übergangen.</summary>
    class function ParseChecks(const AText: string): TAtlasTextChecks; static;
    /// <summary>Gruppen durch „;“, Begriffe durch „,“ getrennt; Gruppen mit weniger als zwei Begriffen
    /// entfallen.</summary>
    class function ParseSynonyms(const AText: string): TArray<TArray<string>>; static;
    /// <summary>Steht der erste Teil des Pfads (ohne Index) in AExcluded (durch Komma getrennt)?</summary>
    class function Excluded(const APath, AExcluded: string): Boolean; static;
    /// <summary>Großbuchstabe nach „&amp;“ (nicht „&amp;&amp;“); #0 ohne.</summary>
    class function AcceleratorOf(const AText: string): Char; static;
    /// <summary>Kopie von AEntries mit den Hinweisen der eingeschalteten Prüfungen.</summary>
    class function Check(const AEntries: TArray<TAtlasTextEntry>; AChecks: TAtlasTextChecks;
      const ASynonyms: TArray<TArray<string>>): TArray<TAtlasTextEntry>; static;
    /// <summary>Freitext in Komponente, Klasse, Eigenschaft oder Text; mit AOnlyFindings nur Einträge mit
    /// Hinweis.</summary>
    class function Matches(const AEntry: TAtlasTextEntry; const AFilter: string;
      AOnlyFindings: Boolean): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Character;

type
  TWordRef = record
    Key: string;
    Spelling: string;
  end;

const
  cCheckNames: array [TAtlasTextCheck] of string = ('accelerators', 'variants', 'truncated', 'whitespace',
    'labelColon');

{ TAtlasTextEntry }

class function TAtlasTextEntry.Create(const AComponent, AClassName, APath, AText, AGroup: string): TAtlasTextEntry;
begin
  Result.Component := AComponent;
  Result.ClassName := AClassName;
  Result.Path := APath;
  Result.Text := AText;
  Result.Group := AGroup;
  Result.NeedsColon := False;
  Result.Truncated := False;
  Result.Findings := nil;
end;

function TAtlasTextEntry.HasFindings: Boolean;
begin
  Result := Length(Findings) > 0;
end;

function Finding(ACheck: TAtlasTextCheck; const ADetail: string): TAtlasTextFinding;
begin
  Result.Check := ACheck;
  Result.Detail := ADetail;
end;

{ TAtlasFormTexts }

class function TAtlasFormTexts.ParseChecks(const AText: string): TAtlasTextChecks;
var
  mPart: string;
  mCheck: TAtlasTextCheck;
begin
  Result := [];
  for mPart in AText.Split([',', ';']) do
  begin
    for mCheck := Low(TAtlasTextCheck) to High(TAtlasTextCheck) do
    begin
      if SameText(Trim(mPart), cCheckNames[mCheck]) then
      begin
        Include(Result, mCheck);
      end;
    end;
  end;
end;

class function TAtlasFormTexts.ParseSynonyms(const AText: string): TArray<TArray<string>>;
var
  mGroup, mTerm: string;
  mTerms: TArray<string>;
begin
  Result := nil;
  for mGroup in AText.Split([';']) do
  begin
    mTerms := nil;
    for mTerm in mGroup.Split([',']) do
    begin
      if Trim(mTerm) <> '' then
      begin
        mTerms := mTerms + [Trim(mTerm)];
      end;
    end;
    if Length(mTerms) >= 2 then
    begin
      Result := Result + [mTerms];
    end;
  end;
end;

class function TAtlasFormTexts.Excluded(const APath, AExcluded: string): Boolean;
var
  mHead, mName: string;
  mCut: Integer;
begin
  mHead := APath;
  mCut := Pos('.', mHead);
  if mCut > 0 then
  begin
    mHead := Copy(mHead, 1, mCut - 1);
  end;
  mCut := Pos('[', mHead);
  if mCut > 0 then
  begin
    mHead := Copy(mHead, 1, mCut - 1);
  end;
  for mName in AExcluded.Split([',', ';']) do
  begin
    if SameText(Trim(mName), mHead) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasFormTexts.AcceleratorOf(const AText: string): Char;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while mIndex < Length(AText) do
  begin
    if AText[mIndex] = '&' then
    begin
      if AText[mIndex + 1] <> '&' then
      begin
        Exit(AText[mIndex + 1].ToUpper);
      end;
      Inc(mIndex);
    end;
    Inc(mIndex);
  end;
  Result := #0;
end;

/// <summary>Schlüssel eines Worts: klein, ohne Bindestriche.</summary>
function KeyOf(const AWord: string): string;
begin
  Result := LowerCase(StringReplace(AWord, '-', '', [rfReplaceAll]));
end;

/// <summary>Schreibweise ohne den ersten Buchstaben als Unterschied (Satzanfang).</summary>
function SpellingOf(const AWord: string): string;
begin
  Result := AWord;
  if Result <> '' then
  begin
    Result[1] := Result[1].ToLower;
  end;
end;

/// <summary>Synonymgruppe von AKey als „#n“; sonst AKey.</summary>
function GroupKey(const AKey: string; const ASynonyms: TArray<TArray<string>>): string;
var
  mGroup: Integer;
  mTerm: string;
begin
  for mGroup := 0 to High(ASynonyms) do
  begin
    for mTerm in ASynonyms[mGroup] do
    begin
      if KeyOf(mTerm) = AKey then
      begin
        Exit('#' + IntToStr(mGroup));
      end;
    end;
  end;
  Result := AKey;
end;

/// <summary>Wörter aus Buchstaben, Ziffern und Bindestrichen, ohne „&amp;“, mindestens zwei Zeichen.</summary>
function WordsOf(const AText: string; const ASynonyms: TArray<TArray<string>>): TArray<TWordRef>;
var
  mText, mWord: string;
  mIndex, mStart: Integer;
  mRef: TWordRef;
begin
  Result := nil;
  mText := StringReplace(AText, '&', '', [rfReplaceAll]) + ' ';
  mStart := 1;
  for mIndex := 1 to Length(mText) do
  begin
    if mText[mIndex].IsLetterOrDigit or (mText[mIndex] = '-') then
    begin
      Continue;
    end;
    mWord := Copy(mText, mStart, mIndex - mStart);
    mStart := mIndex + 1;
    while StartsStr('-', mWord) do
    begin
      Delete(mWord, 1, 1);
    end;
    while EndsStr('-', mWord) do
    begin
      Delete(mWord, Length(mWord), 1);
    end;
    if Length(KeyOf(mWord)) >= 2 then
    begin
      mRef.Key := GroupKey(KeyOf(mWord), ASynonyms);
      mRef.Spelling := mWord;
      Result := Result + [mRef];
    end;
  end;
end;

function Contains(const AList: TArray<string>; const AValue: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if mItem = AValue then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Andere Schreibweisen von ARef in allen Einträgen.</summary>
function OthersOf(const ARef: TWordRef; const AWords: TArray<TArray<TWordRef>>): TArray<string>;
var
  mEntry: TArray<TWordRef>;
  mOther: TWordRef;
begin
  Result := nil;
  for mEntry in AWords do
  begin
    for mOther in mEntry do
    begin
      if (mOther.Key = ARef.Key) and (SpellingOf(mOther.Spelling) <> SpellingOf(ARef.Spelling)) and
        not Contains(Result, mOther.Spelling) then
      begin
        Result := Result + [mOther.Spelling];
      end;
    end;
  end;
end;

procedure AddVariants(var AEntries: TArray<TAtlasTextEntry>; const ASynonyms: TArray<TArray<string>>);
var
  mWords: TArray<TArray<TWordRef>>;
  mIndex: Integer;
  mRef: TWordRef;
  mOthers, mDone: TArray<string>;
begin
  mWords := nil;
  SetLength(mWords, Length(AEntries));
  for mIndex := 0 to High(AEntries) do
  begin
    mWords[mIndex] := WordsOf(AEntries[mIndex].Text, ASynonyms);
  end;
  for mIndex := 0 to High(AEntries) do
  begin
    mDone := nil;
    for mRef in mWords[mIndex] do
    begin
      mOthers := OthersOf(mRef, mWords);
      if (Length(mOthers) > 0) and not Contains(mDone, mRef.Key) then
      begin
        mDone := mDone + [mRef.Key];
        AEntries[mIndex].Findings := AEntries[mIndex].Findings + [Finding(TAtlasTextCheck.Variants,
          mRef.Spelling + ' / ' + string.Join(' / ', mOthers))];
      end;
    end;
  end;
end;

procedure AddAccelerators(var AEntries: TArray<TAtlasTextEntry>);
var
  mIndex, mOther: Integer;
  mKey: Char;
begin
  for mIndex := 0 to High(AEntries) do
  begin
    mKey := TAtlasFormTexts.AcceleratorOf(AEntries[mIndex].Text);
    if (mKey = #0) or (AEntries[mIndex].Group = '') then
    begin
      Continue;
    end;
    for mOther := 0 to High(AEntries) do
    begin
      if (mOther <> mIndex) and SameText(AEntries[mOther].Group, AEntries[mIndex].Group) and
        (TAtlasFormTexts.AcceleratorOf(AEntries[mOther].Text) = mKey) then
      begin
        AEntries[mIndex].Findings := AEntries[mIndex].Findings + [Finding(TAtlasTextCheck.Accelerators,
          '&' + mKey + ': ' + AEntries[mOther].Component)];
        Break;
      end;
    end;
  end;
end;

procedure AddSingle(var AEntry: TAtlasTextEntry; AChecks: TAtlasTextChecks);
begin
  if (TAtlasTextCheck.Truncated in AChecks) and AEntry.Truncated then
  begin
    AEntry.Findings := AEntry.Findings + [Finding(TAtlasTextCheck.Truncated, '')];
  end;
  if (TAtlasTextCheck.Whitespace in AChecks) and ((AEntry.Text <> Trim(AEntry.Text)) or
    (Pos('  ', AEntry.Text) > 0)) then
  begin
    AEntry.Findings := AEntry.Findings + [Finding(TAtlasTextCheck.Whitespace, '')];
  end;
  if (TAtlasTextCheck.LabelColon in AChecks) and AEntry.NeedsColon and (Trim(AEntry.Text) <> '') and
    not EndsText(':', TrimRight(AEntry.Text)) then
  begin
    AEntry.Findings := AEntry.Findings + [Finding(TAtlasTextCheck.LabelColon, '')];
  end;
end;

class function TAtlasFormTexts.Check(const AEntries: TArray<TAtlasTextEntry>; AChecks: TAtlasTextChecks;
  const ASynonyms: TArray<TArray<string>>): TArray<TAtlasTextEntry>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AEntries));
  for mIndex := 0 to High(AEntries) do
  begin
    Result[mIndex] := AEntries[mIndex];
    Result[mIndex].Findings := nil;
  end;
  if TAtlasTextCheck.Accelerators in AChecks then
  begin
    AddAccelerators(Result);
  end;
  if TAtlasTextCheck.Variants in AChecks then
  begin
    AddVariants(Result, ASynonyms);
  end;
  for mIndex := 0 to High(Result) do
  begin
    AddSingle(Result[mIndex], AChecks);
  end;
end;

class function TAtlasFormTexts.Matches(const AEntry: TAtlasTextEntry; const AFilter: string;
  AOnlyFindings: Boolean): Boolean;
var
  mFilter: string;
begin
  mFilter := Trim(AFilter);
  Result := (not AOnlyFindings or AEntry.HasFindings) and ((mFilter = '') or ContainsText(AEntry.Component, mFilter) or
    ContainsText(AEntry.ClassName, mFilter) or ContainsText(AEntry.Path, mFilter) or
    ContainsText(AEntry.Text, mFilter));
end;

end.
