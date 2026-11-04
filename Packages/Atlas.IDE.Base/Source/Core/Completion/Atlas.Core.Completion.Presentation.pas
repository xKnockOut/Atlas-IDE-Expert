unit Atlas.Core.Completion.Presentation;

// Darstellung eines Eintrags in der Liste (#420, #421), ohne Fenster:
//   - Badge: Kürzel und Farbart nach der Art; Funktion oder Prozedur nach
//     der Signatur, solange der Server beides als Methode meldet. Attribute
//     nach "[" (#465) tragen "at" in der Farbe der Typen.
//   - Detail: gedämpfter Text rechts (Typ, Klasse, Unit-Datei).
//   - Tags: "+ Unit" für Einträge aus nicht eingebundenen Units (#180),
//     "deprecated", "constructor"/"destructor", "+2" bei drei Überladungen
//     (#425), "Helper" (#456), "zuletzt"/"häufig" (#418), Anzahl fehlender
//     Werte bei „Alle Werte einfügen“ (#449), "Snippet" bei Code-Vorlagen (#51),
//     "Zweig 0" bei Feldern varianter Records (#846, Id VariantBranch, abschaltbar im Popup).
//   - Geerbte Member (#419): Detail beginnt mit der deklarierenden Klasse.
//   - uses-Abschnitt (#469): kein Dateiname; „bereits im interface-Teil“ bzw. „… implementation-Teil“ für Units
//     aus dem anderen Abschnitt, Marke „Zirkelbezug“ (Fehlerfarbe) für Units, die diese Unit im interface-Teil
//     einbinden. UsesHidden liefert die schon eingebundenen Units für die Fußzeile.
//   - Treffer: Positionen der getippten Zeichen im Namen zum Hervorheben,
//     nach denselben Regeln wie TAtlasCompletionMatcher.

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Style.Palette;

type
  TAtlasBadge = record
    Kind: TAtlasBadgeKind;
    /// <summary>Zwei Buchstaben, z. B. "fn".</summary>
    Code: string;
  end;

  TAtlasTagKind = (Neutral, Accent, Add, Warn, Error);

  /// <summary>Übersetzbare Marken (#446); Plain = Text unverändert zeigen; Cycle = Zirkelbezug im uses-Abschnitt
  /// (#469).</summary>
  TAtlasTagId = (Plain, Recent, Frequent, Cycle, SameParams, Overload, Active, VariantBranch);

  TAtlasTag = record
    Text: string;
    Kind: TAtlasTagKind;
    Id: TAtlasTagId;
    /// <summary>Einzusetzender Wert übersetzbarer Marken, bei VariantBranch die Zweigmarken ("0").</summary>
    Arg: string;
    /// <summary>Mit Fläche in der weichen Farbe der Art (Warnfläche bei „verdeckt …“, #481).</summary>
    Filled: Boolean;
  end;

  TAtlasTags = TArray<TAtlasTag>;

  TAtlasItemPresentation = class
  public
    class function Badge(const AItem: TAtlasCompletionItem): TAtlasBadge; static;
    class function Detail(const AItem: TAtlasCompletionItem): string; static;
    /// <summary>Ansage für Screenreader (#447): "Name, Art, Position von Anzahl. Kurzbeschreibung";
    /// AOf ist das Format von "Position von Anzahl" (z. B. "%d von %d").</summary>
    class function Announcement(const AItem: TAtlasCompletionItem; const AKind, AOf: string;
      APosition, ACount: Integer): string; static;
    class function Tags(const AItem: TAtlasCompletionItem): TAtlasTags; static;
    /// <summary>Texte der Tags durch Komma getrennt („deprecated, Helper“): Zustand für UI Automation (#447).
    /// </summary>
    class function TagText(const AItem: TAtlasCompletionItem): string; static;
    /// <summary>Unit, die beim Übernehmen in uses ergänzt wird; '' wenn eingebunden.</summary>
    class function MissingUnit(const AItem: TAtlasCompletionItem): string; static;
    /// <summary>1-basierte Positionen in AName, die APattern trifft; leer ohne Treffer.</summary>
    class function Highlights(const APattern, AName: string): TArray<Integer>; static;
    /// <summary>SQL-Anweisung, aus der die Feld- oder Parameternamen der Liste stammen (#461), für die
    /// Fußzeile; '' bei anderen Listen.</summary>
    class function DataSource(const AItems: TAtlasCompletionItems): string; static;
    /// <summary>Ausgeblendete Arten der Typargumente (#450), "records,enums"; '' ohne.</summary>
    class function HiddenKinds(const AItems: TAtlasCompletionItems): string; static;
    /// <summary>Detailpanel einer Unit im uses-Abschnitt (#469): "unit Name", Pfad, exportierte Typen,
    /// Zirkelbezug und anderer Abschnitt, ohne Anfrage beim Server.</summary>
    class function UsesDetails(const AItem: TAtlasCompletionItem): TAtlasItemDetails; static;
    /// <summary>Schon eingebundene Units für die Fußzeile im uses-Abschnitt (#469); leer sonst.</summary>
    class function UsesHidden(const AItems: TAtlasCompletionItems): TArray<string>; static;
    /// <summary>Ausgelassene abstrakte Vorfahrmethoden für die Fußzeile nach "inherited " (#482); leer sonst.
    /// </summary>
    class function InheritedAbstract(const AItems: TAtlasCompletionItems): TArray<string>; static;
    /// <summary>Ausgeblendete FMX-Varianten aller Einträge für die Fußzeile (#475), ohne Doppelte; leer sonst.
    /// </summary>
    class function SameNameHidden(const AItems: TAtlasCompletionItems): TArray<string>; static;
    /// <summary>AItem mit den Angaben zu gleichnamigen Bezeichnern für das Detailpanel (#475).</summary>
    class procedure AddSameName(const AItem: TAtlasCompletionItem; var ADetails: TAtlasItemDetails); static;
    /// <summary>Nur das Angebot „Mit try…finally absichern“ (#489) in der Liste?</summary>
    class function Guarding(const AItems: TAtlasCompletionItems): Boolean; static;
  end;

implementation

uses
  System.Character,
  System.Math,
  System.StrUtils,
  Atlas.Core.Completion.Matching;

const
  UsesSuffix = ' (uses ergänzen)';

function MakeBadge(AKind: TAtlasBadgeKind; const ACode: string): TAtlasBadge;
begin
  Result.Kind := AKind;
  Result.Code := ACode;
end;

function MakeTag(const AText: string; AKind: TAtlasTagKind): TAtlasTag;
begin
  // Alle Felder auf den Ausgangswert, auch die später hinzugekommenen (Filled, #481).
  Result := Default(TAtlasTag);
  Result.Text := AText;
  Result.Kind := AKind;
  Result.Id := TAtlasTagId.Plain;
  Result.Arg := '';
end;

function IsWordStart(const AName: string; AIndex: Integer): Boolean;
begin
  Result := TAtlasCompletionMatcher.IsWordStart(AName, AIndex);
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
  begin
    Result[Index] := AStart + Index;
  end;
end;

function WordStartPositions(const APattern, AName: string): TArray<Integer>;
var
  PatternIndex, NameIndex: Integer;
begin
  Result := nil;
  PatternIndex := 1;
  for NameIndex := 1 to Length(AName) do
  begin
    if (PatternIndex <= Length(APattern)) and IsWordStart(AName, NameIndex) and
      SameChar(AName[NameIndex], APattern[PatternIndex]) then
    begin
      Result := Result + [NameIndex];
      Inc(PatternIndex);
    end;
  end;
  if PatternIndex <= Length(APattern) then
  begin
    Result := nil;
  end;
end;

/// <summary>Reached[p][n]: Die ersten p Zeichen von APattern passen und enden bei AName[n] (wie
/// MatchesSubsequence, aber mit allen Zwischenständen, um den Weg zurückzuverfolgen).</summary>
function ReachedTable(const APattern, AName: string): TArray<TArray<Boolean>>;
var
  mPatternIndex, mNameIndex: Integer;
  mBefore: Boolean;
begin
  SetLength(Result, Length(APattern) + 1, Length(AName) + 1);
  for mNameIndex := 1 to Length(AName) do
  begin
    Result[1][mNameIndex] := IsWordStart(AName, mNameIndex) and SameChar(AName[mNameIndex], APattern[1]);
  end;
  for mPatternIndex := 2 to Length(APattern) do
  begin
    mBefore := False;
    for mNameIndex := 1 to Length(AName) do
    begin
      Result[mPatternIndex][mNameIndex] := SameChar(AName[mNameIndex], APattern[mPatternIndex]) and
        (Result[mPatternIndex - 1][mNameIndex - 1] or (mBefore and IsWordStart(AName, mNameIndex)));
      mBefore := mBefore or Result[mPatternIndex - 1][mNameIndex - 1];
    end;
  end;
end;

/// <summary>Frühestes Ende des ganzen Musters (Länge APatternLength); 0 ohne.</summary>
function FirstEnd(const AReached: TArray<TArray<Boolean>>; APatternLength: Integer): Integer;
var
  mNameIndex: Integer;
begin
  for mNameIndex := 1 to High(AReached[APatternLength]) do
  begin
    if AReached[APatternLength][mNameIndex] then
    begin
      Exit(mNameIndex);
    end;
  end;
  Result := 0;
end;

/// <summary>Stelle des Zeichens APatternIndex - 1 vor dem Zeichen APatternIndex bei ANameIndex: bevorzugt direkt
/// davor.</summary>
function PreviousEnd(const AReached: TArray<TArray<Boolean>>; APatternIndex, ANameIndex: Integer): Integer;
begin
  if AReached[APatternIndex - 1][ANameIndex - 1] then
  begin
    Exit(ANameIndex - 1);
  end;
  Result := ANameIndex - 2;
  while (Result >= 1) and not AReached[APatternIndex - 1][Result] do
  begin
    Dec(Result);
  end;
end;

function SubsequencePositions(const APattern, AName: string): TArray<Integer>;
var
  mReached: TArray<TArray<Boolean>>;
  mPatternIndex, mNameIndex: Integer;
begin
  Result := nil;
  mReached := ReachedTable(APattern, AName);
  // Frühestes Ende des ganzen Musters, dann rückwärts.
  mNameIndex := FirstEnd(mReached, Length(APattern));
  if mNameIndex = 0 then
  begin
    Exit;
  end;
  SetLength(Result, Length(APattern));
  for mPatternIndex := Length(APattern) downto 1 do
  begin
    Result[mPatternIndex - 1] := mNameIndex;
    if mPatternIndex > 1 then
    begin
      mNameIndex := PreviousEnd(mReached, mPatternIndex, mNameIndex);
    end;
  end;
end;

{ TAtlasItemPresentation }

class function TAtlasItemPresentation.Badge(const AItem: TAtlasCompletionItem): TAtlasBadge;
const
  cKinds: array[TAtlasItemKind] of TAtlasBadgeKind = (TAtlasBadgeKind.Variable, TAtlasBadgeKind.Function_,
    TAtlasBadgeKind.Function_, TAtlasBadgeKind.Procedure_, TAtlasBadgeKind.Function_, TAtlasBadgeKind.Procedure_,
    TAtlasBadgeKind.Property_, TAtlasBadgeKind.Field, TAtlasBadgeKind.Event, TAtlasBadgeKind.Variable,
    TAtlasBadgeKind.Variable, TAtlasBadgeKind.Constant, TAtlasBadgeKind.Type_, TAtlasBadgeKind.Type_,
    TAtlasBadgeKind.Type_, TAtlasBadgeKind.Type_, TAtlasBadgeKind.Type_, TAtlasBadgeKind.Constant,
    TAtlasBadgeKind.Unit_, TAtlasBadgeKind.Keyword, TAtlasBadgeKind.Snippet, TAtlasBadgeKind.XmlDoc);
  cCodes: array[TAtlasItemKind] of string = ('··', 'fn', 'fn', 'pr', 'fn', 'pr', 'pp', 'fd', 'ev', 'va', 'va', 'co',
    'ty', 'ty', 'ty', 'ty', 'ty', 'co', 'un', 'kw', 'sn', 'xd');
var
  mSignature: string;
begin
  if AItem.Attribute then
  begin
    Exit(MakeBadge(TAtlasBadgeKind.Type_, 'at'));
  end;
  // Methode: Funktion oder Prozedur nach der Signatur.
  mSignature := LowerCase(TrimLeft(AItem.Signature));
  if (AItem.Kind = TAtlasItemKind.Method) and (mSignature.StartsWith('procedure') or
    mSignature.StartsWith('destructor')) then
  begin
    Result := MakeBadge(TAtlasBadgeKind.Procedure_, 'pr');
  end
  else
  begin
    Result := MakeBadge(cKinds[AItem.Kind], cCodes[AItem.Kind]);
  end;
end;

class function TAtlasItemPresentation.MissingUnit(const AItem: TAtlasCompletionItem): string;
var
  Edit: TAtlasTextEdit;
  Text: string;
begin
  Result := '';
  if AItem.UnitUsed then
  begin
    Exit;
  end;
  // Der Server nennt die Unit im Detail ("System.Classes (uses ergänzen)").
  if EndsText(UsesSuffix, AItem.Signature) then
  begin
    Exit(Copy(AItem.Signature, 1, Length(AItem.Signature) - Length(UsesSuffix)));
  end;
  // Sonst aus der Ergänzung selbst (", System.Classes" bzw. "uses System.Classes;").
  for Edit in AItem.AdditionalEdits do
  begin
    Text := Trim(Edit.NewText.Replace(',', ' ').Replace(';', ' '));
    if StartsText('uses', Text) and ((Length(Text) = 4) or not Text[5].IsLetter) then
    begin
      Text := Trim(Copy(Text, 5, MaxInt));
    end;
    if Text <> '' then
    begin
      Exit(Text);
    end;
  end;
end;

class function TAtlasItemPresentation.Announcement(const AItem: TAtlasCompletionItem; const AKind, AOf: string;
  APosition, ACount: Integer): string;
var
  Short: string;
begin
  Result := AItem.Name;
  if AKind <> '' then
  begin
    Result := Result + ', ' + AKind;
  end;
  Result := Result + ', ' + Format(AOf, [APosition, ACount]) + '.';
  Short := Detail(AItem);
  if (Short <> '') and not SameText(Short, AItem.Name) then
  begin
    Result := Result + ' ' + Short;
  end;
end;

class function TAtlasItemPresentation.Detail(const AItem: TAtlasCompletionItem): string;
begin
  if MissingUnit(AItem) <> '' then
  begin
    Exit('');
  end;
  // uses-Abschnitt (#469): der Pfad steht im Detailpanel, rechts nur der Hinweis auf den anderen Abschnitt.
  if AItem.UsesGroup <> '' then
  begin
    if AItem.UsesElsewhere <> '' then
    begin
      Exit('bereits im ' + AItem.UsesElsewhere + '-Teil');
    end;
    Exit('');
  end;
  Result := AItem.Signature;
  // Units: nur der Dateiname statt des ganzen Pfads.
  if AItem.Kind = TAtlasItemKind.Unit_ then
  begin
    Result := ExtractFileName(Result);
  end;
  // Geerbt (#419): Herkunft vorn, damit sie beim Kürzen bleibt.
  if (AItem.Depth > 0) and (AItem.DeclaringClass <> '') then
  begin
    if (Result <> '') and not SameText(Result, AItem.DeclaringClass) then
    begin
      Result := AItem.DeclaringClass + ' · ' + Result;
    end
    else
    begin
      Result := AItem.DeclaringClass;
    end;
  end;
end;

class function TAtlasItemPresentation.TagText(const AItem: TAtlasCompletionItem): string;
var
  Tag: TAtlasTag;
begin
  Result := '';
  for Tag in Tags(AItem) do
  begin
    if Result = '' then
    begin
      Result := Tag.Text;
    end
    else
    begin
      Result := Result + ', ' + Tag.Text;
    end;
  end;
end;

/// <summary>Hängt einen Tag an ATags an und liefert seine Stelle.</summary>
function AddTag(var ATags: TAtlasTags; const AText: string; AKind: TAtlasTagKind): Integer;
begin
  ATags := ATags + [MakeTag(AText, AKind)];
  Result := High(ATags);
end;

/// <summary>Hängt einen Tag mit der Kennung AId an.</summary>
procedure AddIdTag(var ATags: TAtlasTags; const AText: string; AKind: TAtlasTagKind; AId: TAtlasTagId);
var
  mIndex: Integer;
begin
  mIndex := AddTag(ATags, AText, AKind);
  ATags[mIndex].Id := AId;
end;

/// <summary>Hängt einen Tag mit Fläche an.</summary>
procedure AddFilledTag(var ATags: TAtlasTags; const AText: string; AKind: TAtlasTagKind);
var
  mIndex: Integer;
begin
  mIndex := AddTag(ATags, AText, AKind);
  ATags[mIndex].Filled := True;
end;

/// <summary>Anonyme Methode, unerreichbarer Zweig, Anzahl, Zirkelbezug, aktive Variante.</summary>
procedure AddLeadTags(const AItem: TAtlasCompletionItem; var ATags: TAtlasTags);
begin
  // Gerüst einer anonymen Methode (#468): der erwartete Typ.
  if AItem.MethodRef <> '' then
  begin
    AddTag(ATags, AItem.MethodRef, TAtlasTagKind.Accent);
  end;
  // Exception-Klassen (#483): Ein früherer Zweig fängt die Klasse schon, dieser würde nie erreicht.
  if AItem.Unreachable <> '' then
  begin
    AddFilledTag(ATags, 'nie erreicht: ' + AItem.Unreachable + ' davor', TAtlasTagKind.Warn);
  end;
  if AItem.Count > 0 then
  begin
    AddTag(ATags, IntToStr(AItem.Count), TAtlasTagKind.Accent);
  end;
  // Zirkelbezug im uses-Abschnitt (#469).
  if AItem.UsesCycle <> '' then
  begin
    AddIdTag(ATags, 'Zirkelbezug', TAtlasTagKind.Error, TAtlasTagId.Cycle);
  end;
  // Gleichnamige Bezeichner (#475): die Variante, die der Compiler wählt.
  if AItem.SameNameActive then
  begin
    AddIdTag(ATags, 'aktiv', TAtlasTagKind.Accent, TAtlasTagId.Active);
  end;
end;

/// <summary>Vollständiger inherited-Aufruf (#482): gleiche Parameter, andere Überladung, sonst die Klasse.</summary>
procedure AddInheritedTag(const AItem: TAtlasCompletionItem; var ATags: TAtlasTags);
begin
  if AItem.InheritedMatch = 'same' then
  begin
    AddIdTag(ATags, 'gleiche Parameter', TAtlasTagKind.Accent, TAtlasTagId.SameParams);
  end
  else if AItem.InheritedMatch = 'overload' then
  begin
    AddIdTag(ATags, 'Überladung', TAtlasTagKind.Neutral, TAtlasTagId.Overload);
  end
  else if (AItem.InheritedMatch = 'other') and (AItem.DeclaringClass <> '') then
  begin
    AddTag(ATags, AItem.DeclaringClass, TAtlasTagKind.Neutral);
  end;
end;

/// <summary>Fehlende Unit, Konstruktor bzw. Destruktor, deprecated.</summary>
procedure AddKindTags(const AItem: TAtlasCompletionItem; var ATags: TAtlasTags);
var
  mMissing, mDirective: string;
begin
  mMissing := TAtlasItemPresentation.MissingUnit(AItem);
  if mMissing <> '' then
  begin
    AddTag(ATags, '+ ' + mMissing, TAtlasTagKind.Add);
  end;
  case AItem.Kind of
    TAtlasItemKind.Constructor_: AddTag(ATags, 'constructor', TAtlasTagKind.Neutral);
    TAtlasItemKind.Destructor_: AddTag(ATags, 'destructor', TAtlasTagKind.Neutral);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  for mDirective in AItem.Directives do
  begin
    if SameText(mDirective, 'deprecated') then
    begin
      AddTag(ATags, 'deprecated', TAtlasTagKind.Warn);
    end;
  end;
end;

/// <summary>Mitglied von Self (#488): Eigenschaft, Feld oder die Klasse, die die Methode deklariert.</summary>
procedure AddMemberTag(const AItem: TAtlasCompletionItem; var ATags: TAtlasTags);
begin
  if AItem.Kind = TAtlasItemKind.Property_ then
  begin
    AddTag(ATags, 'Eigenschaft', TAtlasTagKind.Neutral);
  end
  else if AItem.Kind = TAtlasItemKind.Field then
  begin
    AddTag(ATags, 'Feld', TAtlasTagKind.Neutral);
  end
  else if AItem.DeclaringClass <> '' then
  begin
    AddTag(ATags, AItem.DeclaringClass, TAtlasTagKind.Neutral);
  end;
end;

/// <summary>with-Objekt (#481): Herkunft und, was das Mitglied verdeckt, als Warnung mit Fläche.</summary>
procedure AddWithTags(const AItem: TAtlasCompletionItem; var ATags: TAtlasTags);
var
  mShadow: string;
begin
  if AItem.WithOrigin = '' then
  begin
    Exit;
  end;
  AddTag(ATags, 'aus ' + AItem.WithOrigin, TAtlasTagKind.Accent);
  for mShadow in AItem.WithShadows do
  begin
    AddFilledTag(ATags, 'verdeckt ' + mShadow, TAtlasTagKind.Warn);
  end;
end;

/// <summary>Herkunft (#488): woher ein Name ohne Punkt davor stammt.</summary>
procedure AddScopeTags(const AItem: TAtlasCompletionItem; var ATags: TAtlasTags);
begin
  case AItem.Scope of
    1: AddTag(ATags, 'lokal', TAtlasTagKind.Accent);
    2: AddTag(ATags, 'Parameter', TAtlasTagKind.Accent);
    3: AddMemberTag(AItem, ATags);
    4: AddTag(ATags, 'Unit', TAtlasTagKind.Neutral);
    5:
      if AItem.DeclaringUnit <> '' then
      begin
        AddTag(ATags, AItem.DeclaringUnit, TAtlasTagKind.Neutral);
      end;
    6: AddWithTags(AItem, ATags);
  end;
end;

/// <summary>Bedingte Deklarationen (#476): "nur WIN64"; in der aktiven Konfiguration nicht vorhanden als
/// Warnung.</summary>
procedure AddConditionTag(const AItem: TAtlasCompletionItem; var ATags: TAtlasTags);
begin
  if SameText(AItem.Condition, 'platform') then
  begin
    AddTag(ATags, 'platform', TAtlasTagKind.Warn);
  end
  else if AItem.Condition <> '' then
  begin
    if AItem.Unavailable then
    begin
      AddTag(ATags, 'nur ' + AItem.Condition, TAtlasTagKind.Warn);
    end
    else
    begin
      AddTag(ATags, 'nur ' + AItem.Condition, TAtlasTagKind.Neutral);
    end;
  end;
end;

/// <summary>Zweig, Überladungen, Helper, Vorlagen, Sender, Typkonvertierung.</summary>
procedure AddDetailTags(const AItem: TAtlasCompletionItem; var ATags: TAtlasTags);
var
  mIndex: Integer;
begin
  // Felder varianter Records (#846): „Zweig 0“.
  if AItem.VariantBranch <> '' then
  begin
    mIndex := AddTag(ATags, 'Zweig ' + AItem.VariantBranch, TAtlasTagKind.Neutral);
    ATags[mIndex].Id := TAtlasTagId.VariantBranch;
    ATags[mIndex].Arg := AItem.VariantBranch;
  end;
  if AItem.OverloadCount > 1 then
  begin
    AddTag(ATags, '+' + IntToStr(AItem.OverloadCount - 1), TAtlasTagKind.Neutral);
  end;
  if AItem.IsHelper then
  begin
    AddTag(ATags, 'Helper', TAtlasTagKind.Accent);
  end;
  // Postfix-Vorlagen (#188) und Code-Vorlagen (#51).
  if AItem.Postfix then
  begin
    AddTag(ATags, 'Postfix', TAtlasTagKind.Neutral);
  end
  else if AItem.Snippet <> '' then
  begin
    AddTag(ATags, 'Snippet', TAtlasTagKind.Neutral);
  end;
  // Sender mit Typumwandlung (#480).
  if AItem.Sender <> '' then
  begin
    AddTag(ATags, 'als ' + AItem.Sender, TAtlasTagKind.Accent);
  end;
  // Typkonvertierung (#490).
  if AItem.Conversion <> '' then
  begin
    AddTag(ATags, '→ ' + AItem.Conversion, TAtlasTagKind.Accent);
  end;
end;

/// <summary>Lernende Gewichtung (#418): zuletzt bzw. häufig gewählt.</summary>
procedure AddUsageTag(const AItem: TAtlasCompletionItem; var ATags: TAtlasTags);
begin
  case AItem.Usage of
    TAtlasUsageMark.Recent: AddIdTag(ATags, 'zuletzt', TAtlasTagKind.Accent, TAtlasTagId.Recent);
    TAtlasUsageMark.Frequent: AddIdTag(ATags, 'häufig', TAtlasTagKind.Neutral, TAtlasTagId.Frequent);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TAtlasItemPresentation.Tags(const AItem: TAtlasCompletionItem): TAtlasTags;
begin
  Result := nil;
  AddLeadTags(AItem, Result);
  AddInheritedTag(AItem, Result);
  AddKindTags(AItem, Result);
  AddScopeTags(AItem, Result);
  AddConditionTag(AItem, Result);
  AddDetailTags(AItem, Result);
  AddUsageTag(AItem, Result);
end;

class function TAtlasItemPresentation.Highlights(const APattern, AName: string): TArray<Integer>;
var
  Score, Found: Integer;
begin
  Result := nil;
  Score := TAtlasCompletionMatcher.Score(APattern, AName);
  if (APattern = '') or (Score = TAtlasCompletionMatcher.NoMatch) then
  begin
    Exit;
  end;
  if Score >= TAtlasCompletionMatcher.ScorePrefix then
  begin
    Exit(Range(1, Length(APattern)));
  end;
  if Score = TAtlasCompletionMatcher.ScoreWordStarts then
  begin
    Exit(WordStartPositions(APattern, AName));
  end;
  if Score = TAtlasCompletionMatcher.ScoreSubstring then
  begin
    Found := Pos(APattern.ToUpper, AName.ToUpper);
    Exit(Range(Found, Length(APattern)));
  end;
  Result := SubsequencePositions(APattern, AName);
end;

class function TAtlasItemPresentation.HiddenKinds(const AItems: TAtlasCompletionItems): string;
var
  Item: TAtlasCompletionItem;
begin
  for Item in AItems do
  begin
    if Item.HiddenKinds <> '' then
    begin
      Exit(Item.HiddenKinds);
    end;
  end;
  Result := '';
end;

class function TAtlasItemPresentation.DataSource(const AItems: TAtlasCompletionItems): string;
var
  Item: TAtlasCompletionItem;
begin
  for Item in AItems do
  begin
    if Item.DataSource <> '' then
    begin
      Exit(Item.DataSource);
    end;
  end;
  Result := '';
end;

class function TAtlasItemPresentation.UsesDetails(const AItem: TAtlasCompletionItem): TAtlasItemDetails;
begin
  Result := Default(TAtlasItemDetails);
  Result.Declaration := 'unit ' + AItem.Name;
  Result.UnitPath := AItem.Signature;
  Result.UnitTypes := AItem.UsesTypes;
  Result.UnitTypeCount := Max(AItem.UsesTypeCount, Length(AItem.UsesTypes));
  Result.UsesCycle := AItem.UsesCycle;
  Result.UsesElsewhere := AItem.UsesElsewhere;
end;

class function TAtlasItemPresentation.UsesHidden(const AItems: TAtlasCompletionItems): TArray<string>;
var
  Item: TAtlasCompletionItem;
begin
  for Item in AItems do
  begin
    if Length(Item.UsesHidden) > 0 then
    begin
      Exit(Item.UsesHidden);
    end;
  end;
  Result := nil;
end;

class function TAtlasItemPresentation.InheritedAbstract(const AItems: TAtlasCompletionItems): TArray<string>;
var
  Item: TAtlasCompletionItem;
begin
  for Item in AItems do
  begin
    if Length(Item.InheritedAbstract) > 0 then
    begin
      Exit(Item.InheritedAbstract);
    end;
  end;
  Result := nil;
end;

class function TAtlasItemPresentation.SameNameHidden(const AItems: TAtlasCompletionItems): TArray<string>;
var
  Item: TAtlasCompletionItem;
  Name: string;
begin
  Result := nil;
  for Item in AItems do
  begin
    for Name in Item.SameNameHidden do
    begin
      if not MatchText(Name, Result) then
      begin
        Result := Result + [Name];
      end;
    end;
  end;
end;

class procedure TAtlasItemPresentation.AddSameName(const AItem: TAtlasCompletionItem;
  var ADetails: TAtlasItemDetails);
begin
  ADetails.SameNameUnits := AItem.SameNameUnits;
  ADetails.SameNameHidden := AItem.SameNameHidden;
  if Length(AItem.SameNameUnits) = 0 then
  begin
    ADetails.SameNameThis := '';
  end
  else
  begin
    ADetails.SameNameThis := AItem.DeclaringUnit;
  end;
  ADetails.SameNameInsert := AItem.SameNameInsert;
end;

class function TAtlasItemPresentation.Guarding(const AItems: TAtlasCompletionItems): Boolean;
var
  Item: TAtlasCompletionItem;
begin
  Result := Length(AItems) > 0;
  for Item in AItems do
  begin
    if not Item.Guard then
    begin
      Exit(False);
    end;
  end;
end;

end.
