unit Atlas.Common.Mcp.DocsIndex;

// Suchindex für das MCP-Werkzeug search_atlas_docs (#2376): Regeln aus dem Regelkatalog, Einstellungen,
// Tastenkürzel und Abschnitte der Funktionsseiten aus dem eingebetteten Index (Atlas.Common.Mcp.DocsIndexData,
// erzeugt von Tools/Update-ConfigDoc.ps1). Die Suche gewichtet Kennung, Name und Überschrift vor dem Fließtext,
// faltet Groß-/Kleinschreibung und Umlaute und sucht bei Regeln und Einstellungen in beiden Sprachen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Rules.Catalog;

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Eintrags; Feature = Abschnitt einer Funktionsseite ohne eigenes Fenster.</summary>
  TDocsKind = (All, Rule, Setting, Window, Feature, Command);
{$SCOPEDENUMS OFF}

  /// <summary>Gefalteter Suchtext eines Eintrags mit seinem Gewicht.</summary>
  TDocsField = record
    Text: string;
    Weight: Integer;
  end;

  TDocsEntry = record
    Kind: TDocsKind;
    Id: string;
    /// <summary>Eintrag des eingebetteten Index; nil bei Regeln. Gehört dem Index.</summary>
    Item: TJSONObject;
    /// <summary>Regel in der Sprache der Anfrage; nur bei Kind = Rule.</summary>
    Rule: TRuleCatalogEntry;
    Fields: TArray<TDocsField>;
  end;

  TDocsHit = record
    Entry: TDocsEntry;
    Score: Integer;
    /// <summary>Die Anfrage ist genau die Kennung (Regel, Schlüssel, Fenster).</summary>
    Exact: Boolean;
  end;

  TDocsIndex = class
  public const
    cWeightId = 8;
    cWeightName = 5;
    cWeightKeyword = 4;
    cWeightPlace = 3;
    cWeightText = 1;
  private
    FItems: TJSONValue;
    FEntries: TArray<TDocsEntry>;
    procedure AddRules(ACatalog, AOther: TRuleCatalog);
    procedure AddItems(ALanguage: TTextLanguage);
  public
    /// <summary>Index aus AJson (Array wie AtlasDocsIndexJson) und den Regeln aus ACatalog (Sprache der Anfrage);
    /// AOther liefert die Namen und Beschreibungen der anderen Sprache für die Suche (nil = ohne).</summary>
    constructor Create(const AJson: string; ALanguage: TTextLanguage; ACatalog, AOther: TRuleCatalog);
    destructor Destroy; override;
    /// <summary>Treffer nach Gewicht, höchstens ALimit; eine genaue Kennung zuerst.</summary>
    function Search(const AQuery: string; AKind: TDocsKind; ALimit: Integer): TArray<TDocsHit>;
    /// <summary>Bis zu ACount Kennungen mit kleinem Editierabstand zur Anfrage.</summary>
    function Similar(const AQuery: string; AKind: TDocsKind; ACount: Integer): TArray<string>;
    function Entries: TArray<TDocsEntry>;
    /// <summary>Klein, Umlaute ausgeschrieben (ä → ae, ß → ss).</summary>
    class function Fold(const AText: string): string; static;
    /// <summary>Suchwörter der Anfrage: gefaltet, ohne Füllwörter und ohne Wörter unter zwei Zeichen.</summary>
    class function Words(const AQuery: string): TArray<string>; static;
    class function KindName(AKind: TDocsKind): string; static;
    class function TryParseKind(const AText: string; out AKind: TDocsKind): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Fuzzy,
  Atlas.Text.Json;

const
  cKindNames: array[TDocsKind] of string = ('all', 'rule', 'setting', 'window', 'feature', 'command');
  cExactScore = 100000;
  cMaxDistance = 3;
  // Füllwörter und Verben rund um Ein- und Ausschalten: Sie stehen in fast jeder Frage, aber in keinem Namen.
  cStopWords: array[0..68] of string = ('der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen', 'und',
    'oder', 'wie', 'ich', 'man', 'mit', 'von', 'fuer', 'im', 'in', 'am', 'an', 'ab', 'auf', 'aus', 'zu', 'was', 'wo',
    'welche', 'welcher', 'welches', 'kann', 'soll', 'ist', 'sind', 'wird', 'nicht', 'es', 'sich', 'mein', 'meine',
    'schalte', 'schalten', 'abschalten', 'ausschalten', 'einschalten', 'anschalten', 'aktivieren', 'deaktivieren',
    'einstellen', 'the', 'a', 'and', 'or', 'how', 'do', 'to', 'of', 'for', 'on', 'off', 'with', 'is', 'can', 'what',
    'which', 'turn', 'enable', 'disable', 'i');

{ Hilfen }

function Field(const AText: string; AWeight: Integer): TDocsField;
begin
  Result.Text := TDocsIndex.Fold(AText);
  Result.Weight := AWeight;
end;

procedure AddField(var AFields: TArray<TDocsField>; const AText: string; AWeight: Integer);
begin
  if AText <> '' then
  begin
    AFields := AFields + [Field(AText, AWeight)];
  end;
end;

function Text(AItem: TJSONObject; const AName: string): string;
begin
  Result := TJsonRead.Text(AItem, AName);
end;

function KeywordText(AItem: TJSONObject): string;
begin
  Result := string.Join(' ', TJsonRead.Strings(AItem, 'keywords'));
end;

function IsWordChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['a'..'z', '0'..'9', '.', '-', '_']) or (Ord(AChar) > 127);
end;

{ TDocsIndex }

constructor TDocsIndex.Create(const AJson: string; ALanguage: TTextLanguage; ACatalog, AOther: TRuleCatalog);
begin
  inherited Create;
  FItems := TJSONObject.ParseJSONValue(AJson);
  if ACatalog <> nil then
  begin
    AddRules(ACatalog, AOther);
  end;
  AddItems(ALanguage);
end;

destructor TDocsIndex.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TDocsIndex.AddRules(ACatalog, AOther: TRuleCatalog);
var
  mRule, mOther: TRuleCatalogEntry;
  mEntry: TDocsEntry;
begin
  for mRule in ACatalog.Entries do
  begin
    mEntry := Default(TDocsEntry);
    mEntry.Kind := TDocsKind.Rule;
    mEntry.Id := mRule.Id;
    mEntry.Rule := mRule;
    AddField(mEntry.Fields, mRule.Id, cWeightId);
    AddField(mEntry.Fields, mRule.Name, cWeightName);
    AddField(mEntry.Fields, TRuleCatalog.GroupName(mRule.Group), cWeightPlace);
    AddField(mEntry.Fields, mRule.Description, cWeightText);
    if (AOther <> nil) and AOther.TryFind(mRule.Id, mOther) then
    begin
      AddField(mEntry.Fields, mOther.Name, cWeightName);
      AddField(mEntry.Fields, mOther.Description, cWeightText);
    end;
    FEntries := FEntries + [mEntry];
  end;
end;

procedure TDocsIndex.AddItems(ALanguage: TTextLanguage);
var
  mValue: TJSONValue;
  mItem: TJSONObject;
  mEntry: TDocsEntry;
begin
  if not (FItems is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(FItems) do
  begin
    mItem := mValue as TJSONObject;
    mEntry := Default(TDocsEntry);
    mEntry.Item := mItem;
    TryParseKind(Text(mItem, 'kind'), mEntry.Kind);
    if mEntry.Kind in [TDocsKind.Window, TDocsKind.Feature] then
    begin
      if Text(mItem, 'language') <> TAtlasLocale.Code(ALanguage) then
      begin
        Continue;
      end;
      mEntry.Id := Text(mItem, 'window');
      AddField(mEntry.Fields, mEntry.Id, cWeightId);
      AddField(mEntry.Fields, Text(mItem, 'title'), cWeightName);
      AddField(mEntry.Fields, Text(mItem, 'path'), cWeightPlace);
      AddField(mEntry.Fields, Text(mItem, 'text'), cWeightText);
    end
    else
    begin
      mEntry.Id := Text(mItem, 'id');
      AddField(mEntry.Fields, mEntry.Id, cWeightId);
      AddField(mEntry.Fields, Text(mItem, 'caption'), cWeightName);
      AddField(mEntry.Fields, Text(mItem, 'captionEn'), cWeightName);
      AddField(mEntry.Fields, KeywordText(mItem), cWeightKeyword);
      AddField(mEntry.Fields, Text(mItem, 'page') + ' ' + Text(mItem, 'pageEn') + ' ' + Text(mItem, 'node') + ' ' +
        Text(mItem, 'nodeEn'), cWeightPlace);
      AddField(mEntry.Fields, Text(mItem, 'description'), cWeightText);
      AddField(mEntry.Fields, Text(mItem, 'descriptionEn'), cWeightText);
    end;
    FEntries := FEntries + [mEntry];
  end;
end;

function TDocsIndex.Entries: TArray<TDocsEntry>;
begin
  Result := FEntries;
end;

function Matches(AKind, AWanted: TDocsKind): Boolean;
begin
  Result := (AWanted = TDocsKind.All) or (AKind = AWanted) or
    ((AWanted = TDocsKind.Window) and (AKind = TDocsKind.Feature));
end;

function IsExact(const AEntry: TDocsEntry; const AQuery: string): Boolean;
begin
  Result := (AEntry.Id <> '') and (SameText(AEntry.Id, AQuery) or SameText('window-' + AEntry.Id, AQuery));
end;

function ScoreOf(const AEntry: TDocsEntry; const AWords: TArray<string>): Integer;
var
  mWord: string;
  mField: TDocsField;
  mBest: Integer;
begin
  Result := 0;
  for mWord in AWords do
  begin
    mBest := 0;
    for mField in AEntry.Fields do
    begin
      if (mField.Weight > mBest) and (Pos(mWord, mField.Text) > 0) then
      begin
        mBest := mField.Weight;
      end;
    end;
    Result := Result + mBest;
  end;
end;

function CompareHits(const A, B: TDocsHit): Integer;
begin
  Result := B.Score - A.Score;
  if Result = 0 then
  begin
    Result := Ord(A.Entry.Kind) - Ord(B.Entry.Kind);
  end;
  if Result = 0 then
  begin
    Result := CompareText(A.Entry.Id, B.Entry.Id);
  end;
  if Result = 0 then
  begin
    Result := CompareText(TJsonRead.Text(A.Entry.Item, 'path'), TJsonRead.Text(B.Entry.Item, 'path'));
  end;
end;

function TDocsIndex.Search(const AQuery: string; AKind: TDocsKind; ALimit: Integer): TArray<TDocsHit>;
var
  mWords: TArray<string>;
  mEntry: TDocsEntry;
  mHit: TDocsHit;
  mQuery: string;
begin
  Result := nil;
  mQuery := Trim(AQuery);
  mWords := Words(mQuery);
  for mEntry in FEntries do
  begin
    if not Matches(mEntry.Kind, AKind) then
    begin
      Continue;
    end;
    mHit.Entry := mEntry;
    mHit.Exact := IsExact(mEntry, mQuery);
    mHit.Score := ScoreOf(mEntry, mWords);
    if mHit.Exact then
    begin
      mHit.Score := mHit.Score + cExactScore;
    end;
    if mHit.Score > 0 then
    begin
      Result := Result + [mHit];
    end;
  end;
  TArray.Sort<TDocsHit>(Result, TComparer<TDocsHit>.Construct(CompareHits));
  if Length(Result) > ALimit then
  begin
    SetLength(Result, ALimit);
  end;
end;

function TDocsIndex.Similar(const AQuery: string; AKind: TDocsKind; ACount: Integer): TArray<string>;
var
  mEntry: TDocsEntry;
  mDistance: Integer;
  mFound: TList<TPair<Integer, string>>;
  mPair: TPair<Integer, string>;
begin
  Result := nil;
  mFound := TList<TPair<Integer, string>>.Create;
  try
    for mEntry in FEntries do
    begin
      if (mEntry.Id = '') or not Matches(mEntry.Kind, AKind) then
      begin
        Continue;
      end;
      mDistance := TTextFuzzy.EditDistance(Trim(AQuery), mEntry.Id, cMaxDistance);
      if mDistance <= cMaxDistance then
      begin
        mFound.Add(TPair<Integer, string>.Create(mDistance, mEntry.Id));
      end;
    end;
    mFound.Sort(TComparer<TPair<Integer, string>>.Construct(
      function(const A, B: TPair<Integer, string>): Integer
      begin
        Result := A.Key - B.Key;
        if Result = 0 then
        begin
          Result := CompareText(A.Value, B.Value);
        end;
      end));
    for mPair in mFound do
    begin
      if (Length(Result) < ACount) and (IndexText(mPair.Value, Result) < 0) then
      begin
        Result := Result + [mPair.Value];
      end;
    end;
  finally
    mFound.Free;
  end;
end;

class function TDocsIndex.Fold(const AText: string): string;
begin
  Result := LowerCase(AText).Replace('Ä', 'ae').Replace('Ö', 'oe').Replace('Ü', 'ue').Replace('ä', 'ae')
    .Replace('ö', 'oe').Replace('ü', 'ue').Replace('ß', 'ss');
end;

class function TDocsIndex.Words(const AQuery: string): TArray<string>;
var
  mText, mWord: string;
  mIndex, mStart: Integer;
begin
  Result := nil;
  mText := Fold(AQuery) + ' ';
  mStart := 1;
  for mIndex := 1 to Length(mText) do
  begin
    if not IsWordChar(mText[mIndex]) then
    begin
      mWord := Copy(mText, mStart, mIndex - mStart).Trim(['.', '-', '_']);
      if (Length(mWord) >= 2) and (IndexStr(mWord, cStopWords) < 0) and (IndexStr(mWord, Result) < 0) then
      begin
        Result := Result + [mWord];
      end;
      mStart := mIndex + 1;
    end;
  end;
end;

class function TDocsIndex.KindName(AKind: TDocsKind): string;
begin
  Result := cKindNames[AKind];
end;

class function TDocsIndex.TryParseKind(const AText: string; out AKind: TDocsKind): Boolean;
var
  mKind: TDocsKind;
begin
  for mKind := Low(TDocsKind) to High(TDocsKind) do
  begin
    if SameText(AText, cKindNames[mKind]) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := TDocsKind.All;
  Result := False;
end;

end.
