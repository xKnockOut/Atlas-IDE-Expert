unit Atlas.Core.Commands.KeyScan;

// Entscheidungen beim Einsammeln der Tastenkürzel (#520, #1967), ohne VCL und
// Open Tools API. Atlas.IDE.Commands.KeyMap liest Aktionen, Tastaturbelegungen
// und Einstellungen der IDE und fragt hier:
// - welche Atlas-Tasten eine Zeile bekommen, an welchem Platz der Anmeldung
//   und ob Atlas die Taste hält (#494);
// - ob eine Aktion nach ihrer Kategorie zu Atlas gehört und ob „Units suchen“
//   die Aktion „Units“ übernimmt (#777);
// - welche Tasten bei der Tastaturbelegung des Editors abzufragen sind und wie
//   eine gefundene Belegung die Zeilen markiert;
// - unter welchem Befehl eine Zeile gezählt wird (#600);
// - was die Einrichtung (#625), die Befehlspalette (#502) und die Prüfung beim
//   Start aus den ausgewerteten Zeilen nehmen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap;

type
  /// <summary>Konflikt einer Atlas-Taste, den die Prüfung beim Start meldet.</summary>
  TAtlasKeyStartConflict = record
    /// <summary>Zeile der Atlas-Taste.</summary>
    Index: Integer;
    /// <summary>Zeile der anderen Belegung (TAtlasKeyMap.PartnerOf).</summary>
    Partner: Integer;
    /// <summary>Zeile des Gewinners; -1 = niemand hält die Taste.</summary>
    Winner: Integer;
  end;

  TAtlasKeyScan = class
  public const
    /// <summary>Anfang der Kennung jeder Atlas-Zeile; dahinter die Nummer der Funktion.</summary>
    cKeyIdPrefix = 'Atlas.Key.';
    /// <summary>Platz der ersten Tastaturbelegung des Editors hinter allen Aktionen.</summary>
    cFirstBindingOrder = 100;
    /// <summary>Vorsatz der bekannten Belegungen der Standard-Tastaturbelegung (#494).</summary>
    cIdeOwnerPrefix = 'IDE: ';
  public
    /// <summary>Kennung der Atlas-Zeile für AFunc.</summary>
    class function AtlasKeyId(AFunc: TAtlasKeyFunction): string; static;
    /// <summary>Reihenfolge, in der die Komposition die Tasten anmeldet: Bei mehreren Atlas-Belegungen derselben
    /// Taste gilt die zuletzt angemeldete. 0 = keine Bindung (wirkt nur im Designer).</summary>
    class function BindOrderOf(AFunc: TAtlasKeyFunction): Integer; static;
    /// <summary>Atlas-Zeile für AFunc in AItems; -1 ohne.</summary>
    class function IndexOfFunc(const AItems: TArray<TAtlasKeyItem>; AFunc: TAtlasKeyFunction): Integer; static;
    /// <summary>Eigene Zeile für die Atlas-Taste: mit Taste, nicht abgeschaltet und keine übernommene Aktion
    /// (Strg+F12 kommt mit den Aktionen).</summary>
    class function IsListed(const AEntry: TAtlasKeyEntry): Boolean; static;
    /// <summary>Zeile der Atlas-Taste AEntry. Fenster-Tasten halten ihre Taste immer (abgeschaltet kommen sie oben
    /// gar nicht an); sonst wie beim Belegen (#494): frei oder mit Vorrang. AOwnerOf nennt die fremde Belegung
    /// einer Taste ('' = frei).</summary>
    class function AtlasItem(const AEntry: TAtlasKeyEntry; const AKeyText, ACaption: string;
      const AOwnerOf: TFunc<Word, string>): TAtlasKeyItem; static;
    /// <summary>Die von „Units suchen“ übernommene Aktion „Units“ (#777) als Atlas-Zeile: bewusst übernommen, also
    /// mit Vorrang; Platz in der Aktionsliste wie die Aktion selbst.</summary>
    class function UnitSearchItem(AShortCut: Word; const AKeyText, ACaption, ACategory: string;
      AOrder: Integer): TAtlasKeyItem; static;
    /// <summary>Aktion von Atlas nach ihrer Kategorie: „Atlas“ oder „Atlas.…“.</summary>
    class function IsAtlasCategory(const ACategory: string): Boolean; static;
    /// <summary>Übernahme der Aktion „Units“ eingeschaltet: Taste UnitSearchIde nicht abgeschaltet.</summary>
    class function UnitSearchTakenOver(const AEntries: TArray<TAtlasKeyEntry>): Boolean; static;
    /// <summary>Befehl einer bekannten Belegung der IDE ohne Vorsatz „IDE: “.</summary>
    class function KnownIdeCommand(const AOwner: string): string; static;
    /// <summary>Abzufragende Tasten: alle Zeilen, dazu Strg/Alt mit Buchstaben, Ziffern, Leer und Enter sowie
    /// F1–F12 mit jeder Umschaltung; jede Taste einmal.</summary>
    class function ProbeKeys(const AItems: TArray<TAtlasKeyItem>): TArray<Word>; static;
    /// <summary>Atlas-Belegung von AKey als wirksam markieren; nur eindeutig, wenn genau eine Atlas-Belegung die
    /// Taste hat.</summary>
    class procedure MarkAtlasBinding(AItems: TList<TAtlasKeyItem>; AKey: Word); static;
    /// <summary>Belegung der IDE auf AKey: vorhandene IDE-Zeile wirksam, Ergebnis False. True, wenn es keine gibt
    /// und die Taste auch Atlas oder einer Erweiterung gehört: Dann braucht die Belegung eine neue Zeile.</summary>
    class function MarkIdeBinding(AItems: TList<TAtlasKeyItem>; AKey: Word): Boolean; static;
    /// <summary>Befehl, unter dem die Zählung einer Zeile steht (#600); '' ohne (Fenster-Tasten, fremde
    /// Tastaturbelegungen).</summary>
    class function UsageIdOf(const AItem: TAtlasKeyItem): string; static;
    /// <summary>Atlas-Taste für die Einrichtung (#625): Vorrang zählt nur, wenn Atlas die Taste auch wirklich hat;
    /// AOwner ist bei Konflikt die andere Belegung, sonst ''.</summary>
    class function SetupEntry(const AItems: TArray<TAtlasKeyItem>; const AEntry: TAtlasKeyEntry;
      out AOwner: string): TAtlasKeyEntry; static;
    /// <summary>Tasten der Befehlspalette (#502): je Befehl die erste Taste, die Atlas hält. AOwnerOf nennt die
    /// fremde Belegung einer Taste ('' = frei).</summary>
    class function HeldCommandKeys(const AEntries: TArray<TAtlasKeyEntry>;
      const AOwnerOf: TFunc<Word, string>): TArray<TAtlasKeyEntry>; static;
    /// <summary>Zu meldende Konflikte beim Start: Atlas-Tasten mit offenem Konflikt und anderer Belegung, ohne die,
    /// die AReported schon meldet (#494).</summary>
    class function StartConflicts(const AItems: TArray<TAtlasKeyItem>;
      const AReported: TFunc<Word, Boolean>): TArray<TAtlasKeyStartConflict>; static;
  end;

implementation

uses
  Atlas.Core.Commands.ShortcutTips;

const
  // Reihenfolge, in der die Komposition die Tasten anmeldet (RebindKeys); bei mehreren Atlas-Belegungen
  // derselben Taste gilt die zuletzt angemeldete. 3 = Editorbefehle (eine Bindung); Strg+F12 (#777) ist keine
  // Bindung, sondern eine Aktion und bekommt ihren Platz in der Aktionsliste.
  cBindOrder: array[TAtlasKeyFunction] of Integer = (1, 2, 4, 5, 6, 7, 3, 3, 3, 3, 3, 3, 3, 8, 3, 3, 3, 3, 0, 3, 3, 3,
    8, 8, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    // Mehrfachmarken (#589): Editorbefehle.
    3, 3, 3, 3, 3,
    // Atlas-Suche (#877, #878): Editorbefehle.
    3, 3, 3, 3,
    // Formatieren (#43): Editorbefehl.
    3,
    // Blockkommentar umschalten (#703): Editorbefehl.
    3,
    // Neue Zeile ober- oder unterhalb (#700): Editorbefehle.
    3, 3,
    // Umschließung entfernen (#657): Editorbefehl.
    3,
    // Fenster „Atlas-Prüfung“ (#909): Editorbefehl.
    3,
    // Abschnittsknöpfe der Editorleiste (#1101): Editorbefehle.
    3, 3,
    // Schnelle Lesezeichen (#1104): Editorbefehle.
    3, 3, 3, 3, 3,
    // Ersetzen in der Atlas-Suche (#893): Editorbefehl.
    3,
    // Gezielt hineinspringen (#836): Editorbefehl.
    3,
    // Typ des markierten Ausdrucks (#689): Editorbefehl.
    3,
    // Sicher löschen (#716): Editorbefehl.
    3,
    // Issue anlegen (#1268): Editorbefehl.
    3,
    // Komponenten suchen (#1442): keine Bindung, TAtlasKeyHook nur im Designer.
    0,
    // Datei jetzt prüfen (#1744): Editorbefehl.
    3,
    // Neue Zeile am Ende des Abschnitts (#1768): Editorbefehl.
    3,
    // Auswahl speichern (#739): keine Bindung, wirkt nur im Designer (Modul Designer).
    0,
    // Im Designer zeigen (#511): Editorbefehl.
    3,
    // Text im Designer bearbeiten (#748): keine Bindung, wirkt nur im Designer (Modul Designer).
    0,
    // Auswahlleiste und Lupe im Designer: keine Bindung, wirken nur im Designer (Modul Designer).
    0, 0,
    // Verwendungen im Code (#750): keine Bindung, wirkt nur im Designer (Modul Designer).
    0,
    // Zuletzt benutzte Testliste (#2167): Editorbefehl (Modul Tests).
    3,
    // Erneut anhängen: Befehl des Moduls Debugger.
    3);
  cVkSpace = $20;
  cVkReturn = $0D;
  cVkF1 = $70;
  cVkF12 = $7B;

{ TAtlasKeyScan }

class function TAtlasKeyScan.AtlasKeyId(AFunc: TAtlasKeyFunction): string;
begin
  Result := cKeyIdPrefix + IntToStr(Ord(AFunc));
end;

class function TAtlasKeyScan.BindOrderOf(AFunc: TAtlasKeyFunction): Integer;
begin
  Result := cBindOrder[AFunc];
end;

class function TAtlasKeyScan.IndexOfFunc(const AItems: TArray<TAtlasKeyItem>; AFunc: TAtlasKeyFunction): Integer;
var
  mIndex: Integer;
  mId: string;
begin
  Result := -1;
  mId := AtlasKeyId(AFunc);
  for mIndex := 0 to High(AItems) do
  begin
    if (AItems[mIndex].Origin = TAtlasKeyOrigin.Atlas) and (AItems[mIndex].Id = mId) then
    begin
      Result := mIndex;
      Exit;
    end;
  end;
end;

class function TAtlasKeyScan.IsListed(const AEntry: TAtlasKeyEntry): Boolean;
begin
  Result := (AEntry.Key <> 0) and not AEntry.Disabled and
    (TAtlasKeyMap.SourceOf(AEntry.Func) <> TAtlasKeySource.Action);
end;

class function TAtlasKeyScan.AtlasItem(const AEntry: TAtlasKeyEntry; const AKeyText, ACaption: string;
  const AOwnerOf: TFunc<Word, string>): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AEntry.Key, AKeyText, ACaption, TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Atlas,
    TAtlasKeyMap.cAtlasName, TAtlasKeyMap.ContextOf(AEntry.Func), TAtlasKeyMap.SourceOf(AEntry.Func),
    AtlasKeyId(AEntry.Func), BindOrderOf(AEntry.Func)));
  Result.Category := TAtlasKeyMap.cAtlasName;
  Result.Func := AEntry.Func;
  Result.Priority := AEntry.Priority;
  Result.Active := (Result.Source = TAtlasKeySource.Window) or
    TAtlasKeyConflicts.ShouldBind(AEntry.Key, AOwnerOf(AEntry.Key), AEntry.Priority);
end;

class function TAtlasKeyScan.UnitSearchItem(AShortCut: Word; const AKeyText, ACaption, ACategory: string;
  AOrder: Integer): TAtlasKeyItem;
const
  cFunc = TAtlasKeyFunction.UnitSearchIde;
begin
  Result := TAtlasKeyItem.Create(AShortCut, AKeyText, ACaption, TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Atlas,
    TAtlasKeyMap.cAtlasName, TAtlasKeyMap.ContextOf(cFunc), TAtlasKeyMap.SourceOf(cFunc), AtlasKeyId(cFunc),
    AOrder));
  Result.Category := ACategory;
  Result.Func := cFunc;
  Result.Priority := True;
end;

class function TAtlasKeyScan.IsAtlasCategory(const ACategory: string): Boolean;
begin
  Result := SameText(ACategory, TAtlasKeyMap.cAtlasName) or ACategory.StartsWith(TAtlasKeyMap.cAtlasName + '.', True);
end;

class function TAtlasKeyScan.UnitSearchTakenOver(const AEntries: TArray<TAtlasKeyEntry>): Boolean;
var
  mEntry: TAtlasKeyEntry;
begin
  Result := False;
  for mEntry in AEntries do
  begin
    if mEntry.Func = TAtlasKeyFunction.UnitSearchIde then
    begin
      Result := not mEntry.Disabled;
    end;
  end;
end;

class function TAtlasKeyScan.KnownIdeCommand(const AOwner: string): string;
begin
  Result := AOwner;
  if Result.StartsWith(cIdeOwnerPrefix) then
  begin
    Result := Copy(Result, Length(cIdeOwnerPrefix) + 1, MaxInt);
  end;
end;

type
  /// <summary>Tasten in fester Reihenfolge, jede einmal.</summary>
  TKeySet = class
  private
    FSeen: TDictionary<Word, Boolean>;
    FKeys: TList<Word>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(AKey: Word);
    function Keys: TArray<Word>;
  end;

constructor TKeySet.Create;
begin
  inherited Create;
  FSeen := TDictionary<Word, Boolean>.Create;
  FKeys := TList<Word>.Create;
end;

destructor TKeySet.Destroy;
begin
  FKeys.Free;
  FSeen.Free;
  inherited Destroy;
end;

procedure TKeySet.Add(AKey: Word);
begin
  if (AKey <> 0) and not FSeen.ContainsKey(AKey) then
  begin
    FSeen.Add(AKey, True);
    FKeys.Add(AKey);
  end;
end;

function TKeySet.Keys: TArray<Word>;
begin
  Result := FKeys.ToArray;
end;

const
  cModifiers: array[0..5] of Word = (TAtlasKeyMap.cScCtrl, TAtlasKeyMap.cScCtrl or TAtlasKeyMap.cScShift,
    TAtlasKeyMap.cScCtrl or TAtlasKeyMap.cScAlt, TAtlasKeyMap.cScCtrl or TAtlasKeyMap.cScAlt or TAtlasKeyMap.cScShift,
    TAtlasKeyMap.cScAlt, TAtlasKeyMap.cScAlt or TAtlasKeyMap.cScShift);

/// <summary>Strg/Alt mit Buchstaben, Ziffern, Leer und Enter.</summary>
procedure AddModifiedKeys(ASet: TKeySet);
var
  mModifier: Word;
  mKey: Integer;
begin
  for mModifier in cModifiers do
  begin
    for mKey := Ord('A') to Ord('Z') do
    begin
      ASet.Add(mModifier or Word(mKey));
    end;
    for mKey := Ord('0') to Ord('9') do
    begin
      ASet.Add(mModifier or Word(mKey));
    end;
    ASet.Add(mModifier or cVkSpace);
    ASet.Add(mModifier or cVkReturn);
  end;
end;

/// <summary>F1–F12 allein, mit Umschalt und mit jeder Umschaltung aus cModifiers.</summary>
procedure AddFunctionKeys(ASet: TKeySet);
var
  mModifier: Word;
  mKey: Integer;
begin
  for mKey := cVkF1 to cVkF12 do
  begin
    ASet.Add(Word(mKey));
    ASet.Add(TAtlasKeyMap.cScShift or Word(mKey));
    for mModifier in cModifiers do
    begin
      ASet.Add(mModifier or Word(mKey));
    end;
  end;
end;

class function TAtlasKeyScan.ProbeKeys(const AItems: TArray<TAtlasKeyItem>): TArray<Word>;
var
  mSet: TKeySet;
  mItem: TAtlasKeyItem;
begin
  mSet := TKeySet.Create;
  try
    for mItem in AItems do
    begin
      mSet.Add(mItem.ShortCut);
    end;
    AddModifiedKeys(mSet);
    AddFunctionKeys(mSet);
    Result := mSet.Keys;
  finally
    mSet.Free;
  end;
end;

class procedure TAtlasKeyScan.MarkAtlasBinding(AItems: TList<TAtlasKeyItem>; AKey: Word);
var
  mIndex, mFound, mCount: Integer;
  mItem: TAtlasKeyItem;
begin
  mFound := -1;
  mCount := 0;
  for mIndex := 0 to AItems.Count - 1 do
  begin
    if (AItems[mIndex].Origin = TAtlasKeyOrigin.Atlas) and (AItems[mIndex].Source = TAtlasKeySource.Binding) and
      (AItems[mIndex].ShortCut = AKey) then
    begin
      mFound := mIndex;
      Inc(mCount);
    end;
  end;
  if mCount = 1 then
  begin
    mItem := AItems[mFound];
    mItem.Effective := True;
    mItem.Active := True;
    AItems[mFound] := mItem;
  end;
end;

class function TAtlasKeyScan.MarkIdeBinding(AItems: TList<TAtlasKeyItem>; AKey: Word): Boolean;
var
  mIndex, mFound: Integer;
  mShared: Boolean;
  mItem: TAtlasKeyItem;
begin
  mFound := -1;
  mShared := False;
  for mIndex := 0 to AItems.Count - 1 do
  begin
    if AItems[mIndex].ShortCut <> AKey then
    begin
      Continue;
    end;
    if (AItems[mIndex].Origin = TAtlasKeyOrigin.Ide) and (AItems[mIndex].Source = TAtlasKeySource.Binding) then
    begin
      mFound := mIndex;
    end;
    mShared := mShared or (AItems[mIndex].Origin <> TAtlasKeyOrigin.Ide);
  end;
  Result := (mFound < 0) and mShared;
  if mFound >= 0 then
  begin
    mItem := AItems[mFound];
    mItem.Effective := True;
    AItems[mFound] := mItem;
  end;
end;

class function TAtlasKeyScan.UsageIdOf(const AItem: TAtlasKeyItem): string;
begin
  Result := '';
  case AItem.Source of
    TAtlasKeySource.Action:
      // Strg+F12 für „Units suchen“ (#777) zählt beim Befehl der Palette.
      if (AItem.Origin = TAtlasKeyOrigin.Atlas) and AItem.Id.StartsWith(cKeyIdPrefix) then
      begin
        Result := TAtlasShortcutTips.AtlasCommandId(AItem.Func);
      end
      else
      begin
        Result := AItem.Id;
      end;
    TAtlasKeySource.Binding:
      if AItem.Origin = TAtlasKeyOrigin.Atlas then
      begin
        Result := TAtlasShortcutTips.AtlasCommandId(AItem.Func);
      end;
  else
    // Fenster-Tasten zählen nicht.
  end;
end;

class function TAtlasKeyScan.SetupEntry(const AItems: TArray<TAtlasKeyItem>; const AEntry: TAtlasKeyEntry;
  out AOwner: string): TAtlasKeyEntry;
var
  mIndex, mPartner: Integer;
begin
  AOwner := '';
  Result := AEntry;
  mIndex := IndexOfFunc(AItems, AEntry.Func);
  if (mIndex < 0) or not AItems[mIndex].Conflict then
  begin
    Exit;
  end;
  mPartner := TAtlasKeyMap.PartnerOf(AItems, mIndex);
  if mPartner >= 0 then
  begin
    AOwner := AItems[mPartner].Holder;
  end;
  Result.Priority := AEntry.Priority and AItems[mIndex].Wins;
end;

class function TAtlasKeyScan.HeldCommandKeys(const AEntries: TArray<TAtlasKeyEntry>;
  const AOwnerOf: TFunc<Word, string>): TArray<TAtlasKeyEntry>;
var
  mEntry: TAtlasKeyEntry;
  mId: string;
  mIds: TDictionary<string, Boolean>;
begin
  Result := nil;
  // Mehrere Tasten für einen Befehl (#775, #777): die erste, die Atlas hält.
  mIds := TDictionary<string, Boolean>.Create;
  try
    for mEntry in AEntries do
    begin
      mId := AnsiLowerCase(TAtlasKeyMap.CommandIdOf(mEntry.Func));
      if (mEntry.Key = 0) or mEntry.Disabled or (mId = '') or mIds.ContainsKey(mId) then
      begin
        Continue;
      end;
      if TAtlasKeyConflicts.ShouldBind(mEntry.Key, AOwnerOf(mEntry.Key), mEntry.Priority) then
      begin
        mIds.Add(mId, True);
        Result := Result + [mEntry];
      end;
    end;
  finally
    mIds.Free;
  end;
end;

class function TAtlasKeyScan.StartConflicts(const AItems: TArray<TAtlasKeyItem>;
  const AReported: TFunc<Word, Boolean>): TArray<TAtlasKeyStartConflict>;
var
  mIndex: Integer;
  mConflict: TAtlasKeyStartConflict;
begin
  Result := nil;
  for mIndex in TAtlasKeyMap.AtlasConflicts(AItems) do
  begin
    if AReported(AItems[mIndex].ShortCut) then
    begin
      Continue;
    end;
    mConflict.Index := mIndex;
    mConflict.Partner := TAtlasKeyMap.PartnerOf(AItems, mIndex);
    mConflict.Winner := AItems[mIndex].Winner;
    if mConflict.Partner >= 0 then
    begin
      Result := Result + [mConflict];
    end;
  end;
end;

end.
