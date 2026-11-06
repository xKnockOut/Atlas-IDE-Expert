unit Atlas.Core.Completion.Favorites;

// Angeheftete Favoriten der Vervollständigung (#458), ohne Fenster und ohne IDE.
//   - Schlüssel wie bei der lernenden Gewichtung (#418): Paar (Typ, Member), Typ = deklarierende Klasse, auf
//     Unit-Ebene die Unit (TAtlasUsage.KeyOf). Ein Favorit von TDataSet.Open gilt damit für jede Datenmenge.
//   - Höchstens MaxPerType Favoriten je Typ. Ein weiterer ersetzt keinen: Toggle meldet Full, die Liste zeigt
//     einen Hinweis in der Fußzeile.
//   - Die Rangfolge (TAtlasRanking) stellt Favoriten vor alle anderen Gruppen, unabhängig von Lernen und Rang,
//     aber nur, wenn sie zum getippten Präfix passen. Der Controller setzt dafür TAtlasCompletionItem.Favorite.
//   - Ablage als JSON (UTF-8), Pfad von der IDE-Schicht (%APPDATA%\Atlas\favorites.json,
//     TAtlasIdeFavorites.FileName). Lesbar ohne Server und ohne IDE über LoadFromFile bzw. Parse, etwa für den
//     Reiter „Gemerkt“ der Willkommensseite (#755):
//       {"version": 1, "favorites": [{"type": "TDataSet", "member": "Open", "kind": "method",
//         "unit": "Data.DB", "signature": "procedure Open", "added": "2026-10-15T09:30:00"}]}
//     Reihenfolge der Einträge = Reihenfolge des Anheftens; "type" ist leer bei Einträgen ohne Typ und Unit
//     (etwa Code-Vorlagen); "added" ist Ortszeit ohne Zeitzone.
//   - Lesen und Schreiben über TAtlasDataFile (Bericht N3): atomar ersetzt; eine unbrauchbare Datei liegt danach
//     als favorites.json.defekt daneben, eine gesperrte bleibt unverändert und wird nicht überschrieben.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Files.DataFile;

{$SCOPEDENUMS ON}

type
  /// <summary>Ergebnis von TAtlasFavorites.Toggle.</summary>
  TAtlasFavoriteToggle = (
    /// <summary>Angeheftet.</summary>
    Added,
    /// <summary>Gelöst.</summary>
    Removed,
    /// <summary>Schon MaxPerType Favoriten bei diesem Typ; nichts geändert.</summary>
    Full,
    /// <summary>Eintrag lässt sich nicht anheften (Aktion, Hinweis, „Alle Werte einfügen“ …).</summary>
    NotAllowed);

  TAtlasFavorite = record
    /// <summary>Typ wie angezeigt, z. B. "TDataSet"; auf Unit-Ebene die Unit, '' ohne beides.</summary>
    TypeName: string;
    /// <summary>Name des Members wie angezeigt, z. B. "Open".</summary>
    Member: string;
    Kind: TAtlasItemKind;
    /// <summary>Unit der Deklaration; '' wenn unbekannt.</summary>
    UnitName: string;
    Signature: string;
    /// <summary>Zeitpunkt des Anheftens (Ortszeit); 0 = unbekannt.</summary>
    Added: TDateTime;
    /// <summary>Schlüssel "typ|member" in Kleinbuchstaben, wie TAtlasUsage.KeyOf.</summary>
    function Key: string;
    /// <summary>"TDataSet.Open", ohne Typ nur "Open".</summary>
    function DisplayName: string;
  end;

  TAtlasFavorites = class
  public const
    MaxPerType = 5;
    FormatVersion = 1;
  private
    FItems: TList<TAtlasFavorite>;
    FChanged: Boolean;
    /// <summary>Vorhandene Datei, die LoadFromFile nicht lesen konnte: SaveToFile überschreibt sie nicht.</summary>
    FKept: string;
    function IndexOf(const AKey: string): Integer;
    function TypeCount(const ATypeKey: string): Integer;
    /// <summary>Hängt AFavorite an, wenn der Schlüssel neu ist und der Typ Platz hat.</summary>
    function TryAdd(const AFavorite: TAtlasFavorite): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Typ von AItem wie angezeigt: deklarierende Klasse, sonst Unit.</summary>
    class function TypeNameOf(const AItem: TAtlasCompletionItem): string; static;
    class function KeyOf(const AItem: TAtlasCompletionItem): string; static;
    /// <summary>Lässt sich AItem anheften? Nicht: Aktionen, Hinweise, „Alle Werte einfügen“, Freigabe
    /// absichern, Interface-Stapel, Deklarationen unbekannter Namen und Einträge ohne Namen.</summary>
    class function CanPin(const AItem: TAtlasCompletionItem): Boolean; static;
    /// <summary>Art als Text der Ablage ("method", "property", …).</summary>
    class function KindName(AKind: TAtlasItemKind): string; static;
    class function KindFromName(const AName: string): TAtlasItemKind; static;
    function IsFavorite(const AItem: TAtlasCompletionItem): Boolean;
    function Contains(const AKey: string): Boolean;
    /// <summary>Favoriten beim Typ ATypeName (Groß-/Kleinschreibung egal).</summary>
    function CountOf(const ATypeName: string): Integer;
    /// <summary>Anheften bzw. lösen; angeheftet wird mit dem aktuellen Zeitpunkt.</summary>
    function Toggle(const AItem: TAtlasCompletionItem): TAtlasFavoriteToggle; overload;
    function Toggle(const AItem: TAtlasCompletionItem; AAdded: TDateTime): TAtlasFavoriteToggle; overload;
    /// <summary>Löst den Favoriten mit AKey; False, wenn es ihn nicht gibt.</summary>
    function Remove(const AKey: string): Boolean;
    procedure Clear;
    function Count: Integer;
    /// <summary>Alle Favoriten in der Reihenfolge des Anheftens.</summary>
    function Items: TArray<TAtlasFavorite>;
    function ToJson: string;
    /// <summary>Ersetzt den Inhalt durch AJson; ungültige Einträge, doppelte und solche über MaxPerType je Typ
    /// fallen weg. False (und leer), wenn AJson kein Objekt mit der Liste "favorites" ist.</summary>
    function Parse(const AJson: string): Boolean;
    /// <summary>Liest die Datei über TAtlasDataFile.Load; fehlt sie oder ist sie unbrauchbar, bleibt die Liste
    /// leer. Ergebnis Kept: Die Datei bleibt unverändert, SaveToFile schreibt sie nicht.</summary>
    function LoadFromFile(const AFileName: string): TAtlasDataLoad;
    /// <summary>Schreibt atomar; False, wenn LoadFromFile die vorhandene Datei nicht lesen konnte.</summary>
    function SaveToFile(const AFileName: string): Boolean;
    /// <summary>Seit dem Laden bzw. Speichern geändert.</summary>
    property Changed: Boolean read FChanged;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Completion.Usage;

const
  KindNames: array[TAtlasItemKind] of string = ('unknown', 'method', 'function', 'procedure', 'constructor',
    'destructor', 'property', 'field', 'event', 'variable', 'parameter', 'constant', 'type', 'class', 'interface',
    'record', 'enum', 'enumMember', 'unit', 'keyword', 'snippet', 'xmlDocTag');

function MakeKey(const ATypeName, AMember: string): string;
begin
  Result := LowerCase(ATypeName) + '|' + LowerCase(AMember);
end;

/// <summary>"2026-10-15T09:30:00", Ortszeit ohne Zeitzone.</summary>
function StampText(AValue: TDateTime): string;
begin
  if AValue <= 0 then
  begin
    Exit('');
  end;
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', AValue);
end;

function TryDigits(const AText: string; AStart, ACount: Integer; out AValue: Word): Boolean;
var
  Index: Integer;
begin
  AValue := 0;
  Result := Length(AText) >= AStart + ACount - 1;
  if not Result then
  begin
    Exit;
  end;
  for Index := AStart to AStart + ACount - 1 do
  begin
    if not CharInSet(AText[Index], ['0'..'9']) then
    begin
      Exit(False);
    end;
    AValue := AValue * 10 + Word(Ord(AText[Index]) - Ord('0'));
  end;
end;

/// <summary>Trennzeichen eines Zeitstempels "yyyy-mm-ddThh:nn:ss" passen.</summary>
function StampShape(const AText: string): Boolean;
begin
  Result := (Length(AText) >= 19) and
    (Copy(AText, 5, 1) + Copy(AText, 8, 1) + Copy(AText, 11, 1) + Copy(AText, 14, 1) + Copy(AText, 17, 1) = '--T::');
end;

function TryDateDigits(const AText: string; out AYear, AMonth, ADay: Word): Boolean;
begin
  Result := TryDigits(AText, 1, 4, AYear) and TryDigits(AText, 6, 2, AMonth) and TryDigits(AText, 9, 2, ADay);
end;

function TryTimeDigits(const AText: string; out AHour, AMinute, ASecond: Word): Boolean;
begin
  Result := TryDigits(AText, 12, 2, AHour) and TryDigits(AText, 15, 2, AMinute) and
    TryDigits(AText, 18, 2, ASecond);
end;

/// <summary>Liest "yyyy-mm-ddThh:nn:ss"; 0 bei allem anderen.</summary>
function ParseStamp(const AText: string): TDateTime;
var
  mYear, mMonth, mDay, mHour, mMinute, mSecond: Word;
  mDate, mTime: TDateTime;
begin
  Result := 0;
  if not StampShape(AText) or not TryDateDigits(AText, mYear, mMonth, mDay) or
    not TryTimeDigits(AText, mHour, mMinute, mSecond) then
  begin
    Exit;
  end;
  if TryEncodeDate(mYear, mMonth, mDay, mDate) and TryEncodeTime(mHour, mMinute, mSecond, 0, mTime) then
  begin
    Result := mDate + mTime;
  end;
end;

{ TAtlasFavorite }

function TAtlasFavorite.Key: string;
begin
  Result := MakeKey(TypeName, Member);
end;

function TAtlasFavorite.DisplayName: string;
begin
  if TypeName = '' then
  begin
    Result := Member;
  end
  else
  begin
    Result := TypeName + '.' + Member;
  end;
end;

{ TAtlasFavorites }

constructor TAtlasFavorites.Create;
begin
  inherited Create;
  FItems := TList<TAtlasFavorite>.Create;
end;

destructor TAtlasFavorites.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

class function TAtlasFavorites.TypeNameOf(const AItem: TAtlasCompletionItem): string;
begin
  Result := AItem.DeclaringClass;
  if Result = '' then
  begin
    Result := AItem.DeclaringUnit;
  end;
end;

class function TAtlasFavorites.KeyOf(const AItem: TAtlasCompletionItem): string;
begin
  Result := TAtlasUsage.KeyOf(AItem);
end;

class function TAtlasFavorites.CanPin(const AItem: TAtlasCompletionItem): Boolean;
begin
  Result := (Trim(AItem.Name) <> '') and not AItem.IsAction and not AItem.Hint and not AItem.Pinned and
    not AItem.Guard and not AItem.Batch and (AItem.Unknown = '');
end;

class function TAtlasFavorites.KindName(AKind: TAtlasItemKind): string;
begin
  Result := KindNames[AKind];
end;

class function TAtlasFavorites.KindFromName(const AName: string): TAtlasItemKind;
var
  Kind: TAtlasItemKind;
begin
  for Kind := Low(TAtlasItemKind) to High(TAtlasItemKind) do
  begin
    if SameText(KindNames[Kind], AName) then
    begin
      Exit(Kind);
    end;
  end;
  Result := TAtlasItemKind.Unknown;
end;

function TAtlasFavorites.IndexOf(const AKey: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to FItems.Count - 1 do
  begin
    if FItems[Index].Key = AKey then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TAtlasFavorites.TypeCount(const ATypeKey: string): Integer;
var
  Favorite: TAtlasFavorite;
begin
  Result := 0;
  for Favorite in FItems do
  begin
    if LowerCase(Favorite.TypeName) = ATypeKey then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasFavorites.TryAdd(const AFavorite: TAtlasFavorite): Boolean;
begin
  Result := (Trim(AFavorite.Member) <> '') and (IndexOf(AFavorite.Key) < 0) and
    (TypeCount(LowerCase(AFavorite.TypeName)) < MaxPerType);
  if Result then
  begin
    FItems.Add(AFavorite);
  end;
end;

function TAtlasFavorites.IsFavorite(const AItem: TAtlasCompletionItem): Boolean;
begin
  Result := (FItems.Count > 0) and (IndexOf(KeyOf(AItem)) >= 0);
end;

function TAtlasFavorites.Contains(const AKey: string): Boolean;
begin
  Result := IndexOf(LowerCase(AKey)) >= 0;
end;

function TAtlasFavorites.CountOf(const ATypeName: string): Integer;
begin
  Result := TypeCount(LowerCase(ATypeName));
end;

function TAtlasFavorites.Toggle(const AItem: TAtlasCompletionItem): TAtlasFavoriteToggle;
begin
  Result := Toggle(AItem, Now);
end;

function TAtlasFavorites.Toggle(const AItem: TAtlasCompletionItem; AAdded: TDateTime): TAtlasFavoriteToggle;
var
  Index: Integer;
  Favorite: TAtlasFavorite;
begin
  if not CanPin(AItem) then
  begin
    Exit(TAtlasFavoriteToggle.NotAllowed);
  end;
  Index := IndexOf(KeyOf(AItem));
  if Index >= 0 then
  begin
    FItems.Delete(Index);
    FChanged := True;
    Exit(TAtlasFavoriteToggle.Removed);
  end;
  Favorite := Default(TAtlasFavorite);
  Favorite.TypeName := TypeNameOf(AItem);
  Favorite.Member := AItem.Name;
  Favorite.Kind := AItem.Kind;
  Favorite.UnitName := AItem.DeclaringUnit;
  Favorite.Signature := AItem.Signature;
  Favorite.Added := AAdded;
  // Ein sechster ersetzt nichts (#458): erst einen anderen lösen.
  if not TryAdd(Favorite) then
  begin
    Exit(TAtlasFavoriteToggle.Full);
  end;
  FChanged := True;
  Result := TAtlasFavoriteToggle.Added;
end;

function TAtlasFavorites.Remove(const AKey: string): Boolean;
var
  Index: Integer;
begin
  Index := IndexOf(LowerCase(AKey));
  Result := Index >= 0;
  if not Result then
  begin
    Exit;
  end;
  FItems.Delete(Index);
  FChanged := True;
end;

procedure TAtlasFavorites.Clear;
begin
  if FItems.Count > 0 then
  begin
    FChanged := True;
  end;
  FItems.Clear;
end;

function TAtlasFavorites.Count: Integer;
begin
  Result := FItems.Count;
end;

function TAtlasFavorites.Items: TArray<TAtlasFavorite>;
begin
  Result := FItems.ToArray;
end;

function TAtlasFavorites.ToJson: string;
var
  Root, Entry: TJSONObject;
  List: TJSONArray;
  Favorite: TAtlasFavorite;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(FormatVersion));
    List := TJSONArray.Create;
    Root.AddPair('favorites', List);
    for Favorite in FItems do
    begin
      Entry := TJSONObject.Create;
      Entry.AddPair('type', Favorite.TypeName);
      Entry.AddPair('member', Favorite.Member);
      Entry.AddPair('kind', KindName(Favorite.Kind));
      Entry.AddPair('unit', Favorite.UnitName);
      Entry.AddPair('signature', Favorite.Signature);
      Entry.AddPair('added', StampText(Favorite.Added));
      List.AddElement(Entry);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TAtlasFavorites.Parse(const AJson: string): Boolean;
var
  Root, List: TJSONValue;
  Value: TJSONValue;
  Entry: TJSONObject;
  Favorite: TAtlasFavorite;
begin
  Result := False;
  FItems.Clear;
  FChanged := False;
  // Ungültiges JSON ergibt nil; was damit geschieht, entscheidet der Aufrufer (TAtlasDataFile.Load).
  Root := TJSONObject.ParseJSONValue(AJson);
  if Root = nil then
  begin
    Exit;
  end;
  try
    if not (Root is TJSONObject) then
    begin
      Exit;
    end;
    List := TJSONObject(Root).GetValue('favorites');
    if not (List is TJSONArray) then
    begin
      Exit;
    end;
    Result := True;
    for Value in TJSONArray(List) do
    begin
      if not (Value is TJSONObject) then
      begin
        Continue;
      end;
      Entry := TJSONObject(Value);
      Favorite := Default(TAtlasFavorite);
      Favorite.TypeName := Entry.GetValue<string>('type', '');
      Favorite.Member := Entry.GetValue<string>('member', '');
      Favorite.Kind := KindFromName(Entry.GetValue<string>('kind', ''));
      Favorite.UnitName := Entry.GetValue<string>('unit', '');
      Favorite.Signature := Entry.GetValue<string>('signature', '');
      Favorite.Added := ParseStamp(Entry.GetValue<string>('added', ''));
      TryAdd(Favorite);
    end;
  finally
    Root.Free;
  end;
end;

function TAtlasFavorites.LoadFromFile(const AFileName: string): TAtlasDataLoad;
begin
  FItems.Clear;
  FChanged := False;
  FKept := '';
  Result := TAtlasDataFile.Load(AFileName, 'Favoriten',
    function(const AText: string): Boolean
    begin
      Result := Parse(AText);
    end);
  if not TAtlasDataFile.Writable(Result) then
  begin
    FKept := AFileName;
  end;
  // Unbrauchbarer Inhalt bleibt nicht halb geladen stehen.
  if Result <> TAtlasDataLoad.Loaded then
  begin
    FItems.Clear;
  end;
end;

function TAtlasFavorites.SaveToFile(const AFileName: string): Boolean;
begin
  Result := not SameFileName(AFileName, FKept);
  if not Result then
  begin
    Exit;
  end;
  TAtlasDataFile.Write(AFileName, ToJson);
  FChanged := False;
end;

end.
