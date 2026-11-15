unit Atlas.Core.Commands.ShortcutTable;

// Tabelle Kürzel → Befehle der Tastenkürzel-Tipps (#600, #1967), ohne VCL und
// Open Tools API. Atlas.IDE.Commands.ShortcutKeys füllt sie aus den Tasten von
// Atlas, den Aktionen und Menüs der IDE (OnBuild) und meldet jeden Tastendruck;
// hier fällt, welche Befehle ein Tastendruck auslöst:
// - ein Kürzel mit Strg oder Alt allein oder als zweiter Schritt nach dem
//   vorigen Tastendruck (Kürzel mit zwei Schritten wie „Strg+K, D“, solange
//   der vorige weniger als TAtlasShortcutTips.cChordMs her ist);
// - eine Taste ohne Umschalttaste nur als zweiter Schritt; sonst vergisst die
//   Tabelle den vorigen Tastendruck.
// Die Tabelle wird nach cMaxAgeMs oder nach Invalidate beim nächsten Gebrauch
// neu gebaut. Beim Aufruf gelernte Kürzel (Learn) überleben den Neubau.
// Zeiten in Millisekunden eines fortlaufenden Zählers; der Aufrufer nennt die
// aktuelle Zeit (ANow).

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TAtlasShortcutTable = class
  public const
    /// <summary>Tabelle spätestens nach dieser Zeit neu bauen.</summary>
    cMaxAgeMs = 30000;
    /// <summary>Selbst gemeldeter Aufruf: dieselbe Aktion so lange danach nicht noch einmal zählen.</summary>
    cExplicitMs = 1000;
  private
    /// <summary>Schlüssel der Tastenfolge (TAtlasShortcutTips.StepsKey) → Befehle.</summary>
    FKeys: TDictionary<string, TArray<string>>;
    /// <summary>Beim Aufruf gelernte Kürzel: Befehl → Text.</summary>
    FLearned: TDictionary<string, string>;
    FBuiltAt: UInt64;
    FPrevKey: Word;
    FPrevAt: UInt64;
    FExplicitId: string;
    FExplicitAt: UInt64;
    FOnBuild: TProc;
    procedure AddSteps(const ASteps: TArray<Word>; const AId: string);
    function IdsOf(const ASteps: TArray<Word>; out AIds: TArray<string>): Boolean;
    procedure EnsureBuilt(ANow: UInt64);
    /// <summary>Befehle zur Taste; AChordOnly: nur als zweiter Schritt. Merkt die Taste für den nächsten Schritt.
    /// </summary>
    function StrokeIds(AShortCut: Word; AChordOnly: Boolean; ANow: UInt64): TArray<string>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Kürzel als Text (auch mit zwei Schritten) für den Befehl AId; leer oder unlesbar nichts.</summary>
    procedure AddText(const AKeyText, AId: string);
    /// <summary>Kürzel AShortCut für den Befehl AId; 0 nichts.</summary>
    procedure AddKey(AShortCut: Word; const AId: string);
    /// <summary>Kürzel eines Befehls außerhalb der Aktionsliste merken; die Tabelle wird neu gebaut.</summary>
    procedure Learn(const AId, AKeyText: string);
    /// <summary>Beim Neubau: die gelernten Kürzel eintragen.</summary>
    procedure AddLearned;
    /// <summary>Beim nächsten Gebrauch neu bauen.</summary>
    procedure Invalidate;
    /// <summary>Der vorige Tastendruck ist so kurz her, dass der nächste sein zweiter Schritt sein kann.</summary>
    function ChordPending(ANow: UInt64): Boolean;
    /// <summary>Befehle, die der Tastendruck AShortCut (Taste mit Umschalttasten) auslöst. AIsShortCut: mit Strg
    /// oder Alt (TAtlasShortcutTips.IsShortCutStroke).</summary>
    function Stroke(AShortCut: Word; AIsShortCut: Boolean; ANow: UInt64): TArray<string>;
    /// <summary>Befehl AId hat sich selbst gemeldet.</summary>
    procedure Explicit(const AId: string; ANow: UInt64);
    /// <summary>AName hat sich vor weniger als cExplicitMs selbst gemeldet.</summary>
    function IsExplicit(const AName: string; ANow: UInt64): Boolean;
    /// <summary>Voriger Tastendruck; 0 ohne.</summary>
    function PrevKey: Word;
    /// <summary>Zeit seit dem vorigen Tastendruck.</summary>
    function PrevAge(ANow: UInt64): UInt64;
    /// <summary>Füllt die Tabelle beim Neubau (nach dem Leeren).</summary>
    property OnBuild: TProc read FOnBuild write FOnBuild;
  end;

implementation

uses
  Atlas.Core.Commands.ShortcutTips;

{ TAtlasShortcutTable }

constructor TAtlasShortcutTable.Create;
begin
  inherited Create;
  FKeys := TDictionary<string, TArray<string>>.Create;
  FLearned := TDictionary<string, string>.Create;
end;

destructor TAtlasShortcutTable.Destroy;
begin
  FLearned.Free;
  FKeys.Free;
  inherited Destroy;
end;

procedure TAtlasShortcutTable.AddSteps(const ASteps: TArray<Word>; const AId: string);
var
  mKey: string;
  mIds: TArray<string>;
begin
  if (Length(ASteps) = 0) or (AId = '') then
  begin
    Exit;
  end;
  mKey := TAtlasShortcutTips.StepsKey(ASteps);
  if not FKeys.TryGetValue(mKey, mIds) then
  begin
    mIds := nil;
  end;
  FKeys.AddOrSetValue(mKey, mIds + [AId]);
end;

function TAtlasShortcutTable.IdsOf(const ASteps: TArray<Word>; out AIds: TArray<string>): Boolean;
begin
  AIds := nil;
  Result := FKeys.TryGetValue(TAtlasShortcutTips.StepsKey(ASteps), AIds);
end;

procedure TAtlasShortcutTable.AddText(const AKeyText, AId: string);
begin
  AddSteps(TAtlasShortcutTips.ParseSteps(AKeyText), AId);
end;

procedure TAtlasShortcutTable.AddKey(AShortCut: Word; const AId: string);
begin
  if AShortCut <> 0 then
  begin
    AddSteps(TArray<Word>.Create(AShortCut), AId);
  end;
end;

procedure TAtlasShortcutTable.Learn(const AId, AKeyText: string);
begin
  if AKeyText <> '' then
  begin
    FLearned.AddOrSetValue(AId, AKeyText);
    Invalidate;
  end;
end;

procedure TAtlasShortcutTable.AddLearned;
var
  mLearned: TPair<string, string>;
begin
  for mLearned in FLearned do
  begin
    AddText(mLearned.Value, mLearned.Key);
  end;
end;

procedure TAtlasShortcutTable.Invalidate;
begin
  FBuiltAt := 0;
end;

procedure TAtlasShortcutTable.EnsureBuilt(ANow: UInt64);
begin
  if (FBuiltAt <> 0) and (ANow - FBuiltAt < cMaxAgeMs) then
  begin
    Exit;
  end;
  FBuiltAt := ANow;
  FKeys.Clear;
  if Assigned(FOnBuild) then
  begin
    FOnBuild();
  end;
end;

function TAtlasShortcutTable.ChordPending(ANow: UInt64): Boolean;
begin
  Result := (FPrevKey <> 0) and (ANow - FPrevAt < TAtlasShortcutTips.cChordMs);
end;

function TAtlasShortcutTable.StrokeIds(AShortCut: Word; AChordOnly: Boolean; ANow: UInt64): TArray<string>;
var
  mIds: TArray<string>;
begin
  EnsureBuilt(ANow);
  Result := nil;
  if not AChordOnly and IdsOf(TArray<Word>.Create(AShortCut), mIds) then
  begin
    Result := mIds;
  end;
  // Zweiter Schritt eines Kürzels mit zwei Schritten.
  if ChordPending(ANow) and IdsOf(TArray<Word>.Create(FPrevKey, AShortCut), mIds) then
  begin
    Result := Result + mIds;
  end;
  FPrevKey := AShortCut;
  FPrevAt := ANow;
end;

function TAtlasShortcutTable.Stroke(AShortCut: Word; AIsShortCut: Boolean; ANow: UInt64): TArray<string>;
begin
  Result := nil;
  if AIsShortCut then
  begin
    Result := StrokeIds(AShortCut, False, ANow);
  end
  // Zweiter Schritt ohne Umschalttaste („Strg+K, D“).
  else if ChordPending(ANow) then
  begin
    Result := StrokeIds(AShortCut, True, ANow);
  end
  else
  begin
    FPrevKey := 0;
  end;
end;

procedure TAtlasShortcutTable.Explicit(const AId: string; ANow: UInt64);
begin
  FExplicitId := AId;
  FExplicitAt := ANow;
end;

function TAtlasShortcutTable.IsExplicit(const AName: string; ANow: UInt64): Boolean;
begin
  Result := SameText(AName, FExplicitId) and (ANow - FExplicitAt < cExplicitMs);
end;

function TAtlasShortcutTable.PrevKey: Word;
begin
  Result := FPrevKey;
end;

function TAtlasShortcutTable.PrevAge(ANow: UInt64): UInt64;
begin
  Result := ANow - FPrevAt;
end;

end.
