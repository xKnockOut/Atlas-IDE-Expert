unit Atlas.Core.Designer.Components;

// Designer-Leiste (#1442), ohne VCL und Windows: Komponenten des Formulars
// nach Namen suchen und im Designer ausblenden.
// - TAtlasDesignerSearch: Teilwortsuche über die Komponentennamen, ohne
//   Groß-/Kleinschreibung. Reihenfolge: gleicher Name, Name beginnt mit dem
//   Suchwort, Wortanfang im Namen (nach „_“ oder vor einem Großbuchstaben,
//   „OK“ in „btnOK“), sonst irgendwo im Namen; bei Gleichstand nach Namen,
//   dann nach Lage im Formular. Step schaltet zyklisch durch die Treffer.
// - TAtlasDesignerHidden: was der Benutzer im Designer ausgeblendet hat:
//   einzelne Namen, ganze Klassen und alle nichtvisuellen Komponenten. Eine
//   ausdrücklich wieder eingeblendete Komponente bleibt sichtbar, auch wenn
//   ihre Klasse ausgeblendet ist. Gemerkt werden Namen, keine Objekte: Der
//   Designer legt Komponenten beim Wiederöffnen neu an.
// Die IDE-Schicht (Atlas.IDE.Designer.Bar) setzt das im Designer um; die
// .dfm bleibt unverändert.

interface

uses
  System.Generics.Collections;

type
  /// <summary>Komponente des Formulars, wie die Leiste sie sieht.</summary>
  TAtlasDesignerItem = record
    Name: string;
    TypeName: string;
    /// <summary>Steuerelement (TControl); False = nichtvisuelle Komponente.</summary>
    Visual: Boolean;
    class function Create(const AName, AClassName: string; AVisual: Boolean): TAtlasDesignerItem; static;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Wie gut ein Name zum Suchwort passt; None = gar nicht.</summary>
  TAtlasDesignerMatch = (Exact, Prefix, WordStart, Contains, None);
{$SCOPEDENUMS OFF}

  TAtlasDesignerSearch = class
  public
    /// <summary>Wie gut passt AName zu APattern (ohne Groß-/Kleinschreibung)? Leeres Suchwort: None.</summary>
    class function MatchOf(const AName, APattern: string): TAtlasDesignerMatch; static;
    /// <summary>Indizes der Treffer in AItems, beste zuerst; leer ohne Suchwort.</summary>
    class function Find(const AItems: TArray<TAtlasDesignerItem>; const APattern: string): TArray<Integer>; static;
    /// <summary>Nächster Treffer von AIndex aus um ADelta (zyklisch); -1 ohne Treffer, 0 von -1 aus vorwärts.
    /// </summary>
    class function Step(AIndex, ACount, ADelta: Integer): Integer; static;
  end;

  TAtlasDesignerHidden = class
  private
    FNames: TDictionary<string, Boolean>;
    /// <summary>Kleingeschrieben → Schreibweise wie in der Klasse.</summary>
    FClasses: TDictionary<string, string>;
    FShown: TDictionary<string, Boolean>;
    FNonVisual: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Ist die Komponente ausgeblendet (einzeln, über ihre Klasse oder als nichtvisuelle)?</summary>
    function IsHidden(const AItem: TAtlasDesignerItem): Boolean;
    /// <summary>Einzelne Komponente aus- bzw. wieder einblenden; Einblenden gilt auch gegen Klasse und
    /// nichtvisuelle.</summary>
    procedure HideName(const AName: string);
    procedure ShowName(const AName: string);
    /// <summary>Alle Komponenten der Klasse ausblenden; gibt ausdrücklich eingeblendete dieser Klasse nicht frei.
    /// </summary>
    procedure HideClass(const AClassName: string);
    /// <summary>Alle nichtvisuellen Komponenten aus- bzw. einblenden.</summary>
    property NonVisual: Boolean read FNonVisual write FNonVisual;
    /// <summary>Alles wieder einblenden.</summary>
    procedure ShowAll;
    /// <summary>Ist überhaupt etwas ausgeblendet (Name, Klasse oder nichtvisuelle)?</summary>
    function Any: Boolean;
    /// <summary>Zahl der ausgeblendeten unter AItems.</summary>
    function CountIn(const AItems: TArray<TAtlasDesignerItem>): Integer;
    /// <summary>Ausgeblendete Klassen in ihrer Schreibweise, sortiert (für das Menü).</summary>
    function HiddenClasses: TArray<string>;
    /// <summary>Klasse wieder einblenden.</summary>
    procedure ShowClass(const AClassName: string);
    function ClassHidden(const AClassName: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Defaults;

function Key(const AText: string): string;
begin
  Result := LowerCase(AText);
end;

{ TAtlasDesignerItem }

class function TAtlasDesignerItem.Create(const AName, AClassName: string; AVisual: Boolean): TAtlasDesignerItem;
begin
  Result.Name := AName;
  Result.TypeName := AClassName;
  Result.Visual := AVisual;
end;

{ TAtlasDesignerSearch }

function IsUpper(AChar: Char): Boolean;
begin
  Result := (AChar >= 'A') and (AChar <= 'Z');
end;

function IsLower(AChar: Char): Boolean;
begin
  Result := ((AChar >= 'a') and (AChar <= 'z')) or ((AChar >= '0') and (AChar <= '9'));
end;

/// <summary>Beginnt an APos (1-basiert) ein Wort im Namen: Anfang, nach „_“, Großbuchstabe nach Kleinbuchstaben.
/// </summary>
function WordStartsAt(const AName: string; APos: Integer): Boolean;
begin
  if APos <= 1 then
    Exit(True);
  if AName[APos - 1] = '_' then
    Exit(True);
  Result := IsUpper(AName[APos]) and IsLower(AName[APos - 1]);
end;

class function TAtlasDesignerSearch.MatchOf(const AName, APattern: string): TAtlasDesignerMatch;
var
  mName, mPattern: string;
  mPos: Integer;
begin
  Result := TAtlasDesignerMatch.None;
  mPattern := Key(Trim(APattern));
  if (mPattern = '') or (AName = '') then
    Exit;
  mName := Key(AName);
  if mName = mPattern then
    Exit(TAtlasDesignerMatch.Exact);
  mPos := Pos(mPattern, mName);
  if mPos = 0 then
    Exit;
  if mPos = 1 then
    Exit(TAtlasDesignerMatch.Prefix);
  Result := TAtlasDesignerMatch.Contains;
  // Weitere Vorkommen: Zählt eins an einem Wortanfang, ist es ein Wortanfang-Treffer.
  while mPos > 0 do
  begin
    if WordStartsAt(AName, mPos) then
      Exit(TAtlasDesignerMatch.WordStart);
    mPos := Pos(mPattern, mName, mPos + 1);
  end;
end;

class function TAtlasDesignerSearch.Find(const AItems: TArray<TAtlasDesignerItem>;
  const APattern: string): TArray<Integer>;
var
  mHits: TList<Integer>;
  mMatches: TArray<TAtlasDesignerMatch>;
  mIndex: Integer;
  mItems: TArray<TAtlasDesignerItem>;
begin
  Result := nil;
  mItems := AItems;
  SetLength(mMatches, Length(AItems));
  mHits := TList<Integer>.Create;
  try
    for mIndex := 0 to High(AItems) do
    begin
      mMatches[mIndex] := MatchOf(AItems[mIndex].Name, APattern);
      if mMatches[mIndex] <> TAtlasDesignerMatch.None then
        mHits.Add(mIndex);
    end;
    // Sort ist nicht stabil: bei Gleichstand eindeutig nach Name, dann nach Lage.
    mHits.Sort(TComparer<Integer>.Construct(
      function(const ALeft, ARight: Integer): Integer
      begin
        Result := Ord(mMatches[ALeft]) - Ord(mMatches[ARight]);
        if Result = 0 then
          Result := CompareText(mItems[ALeft].Name, mItems[ARight].Name);
        if Result = 0 then
          Result := ALeft - ARight;
      end));
    Result := mHits.ToArray;
  finally
    mHits.Free;
  end;
end;

class function TAtlasDesignerSearch.Step(AIndex, ACount, ADelta: Integer): Integer;
begin
  if ACount <= 0 then
    Exit(-1);
  if AIndex < 0 then
  begin
    if ADelta < 0 then
      Exit(ACount - 1);
    Exit(0);
  end;
  Result := (AIndex + ADelta) mod ACount;
  if Result < 0 then
    Inc(Result, ACount);
end;

{ TAtlasDesignerHidden }

constructor TAtlasDesignerHidden.Create;
begin
  inherited Create;
  FNames := TDictionary<string, Boolean>.Create;
  FClasses := TDictionary<string, string>.Create;
  FShown := TDictionary<string, Boolean>.Create;
end;

destructor TAtlasDesignerHidden.Destroy;
begin
  FShown.Free;
  FClasses.Free;
  FNames.Free;
  inherited Destroy;
end;

function TAtlasDesignerHidden.IsHidden(const AItem: TAtlasDesignerItem): Boolean;
begin
  if AItem.Name = '' then
    Exit(False);
  if FNames.ContainsKey(Key(AItem.Name)) then
    Exit(True);
  if FShown.ContainsKey(Key(AItem.Name)) then
    Exit(False);
  Result := FClasses.ContainsKey(Key(AItem.TypeName)) or (FNonVisual and not AItem.Visual);
end;

procedure TAtlasDesignerHidden.HideName(const AName: string);
begin
  if AName = '' then
    Exit;
  FShown.Remove(Key(AName));
  FNames.AddOrSetValue(Key(AName), True);
end;

procedure TAtlasDesignerHidden.ShowName(const AName: string);
begin
  if AName = '' then
    Exit;
  FNames.Remove(Key(AName));
  // Nur merken, wenn sonst noch etwas ganze Gruppen ausblendet.
  if (FClasses.Count > 0) or FNonVisual then
    FShown.AddOrSetValue(Key(AName), True);
end;

procedure TAtlasDesignerHidden.HideClass(const AClassName: string);
begin
  if AClassName <> '' then
    FClasses.AddOrSetValue(Key(AClassName), AClassName);
end;

procedure TAtlasDesignerHidden.ShowClass(const AClassName: string);
begin
  FClasses.Remove(Key(AClassName));
end;

function TAtlasDesignerHidden.ClassHidden(const AClassName: string): Boolean;
begin
  Result := FClasses.ContainsKey(Key(AClassName));
end;

procedure TAtlasDesignerHidden.ShowAll;
begin
  FNames.Clear;
  FClasses.Clear;
  FShown.Clear;
  FNonVisual := False;
end;

function TAtlasDesignerHidden.Any: Boolean;
begin
  Result := (FNames.Count > 0) or (FClasses.Count > 0) or FNonVisual;
end;

function TAtlasDesignerHidden.CountIn(const AItems: TArray<TAtlasDesignerItem>): Integer;
var
  mItem: TAtlasDesignerItem;
begin
  Result := 0;
  for mItem in AItems do
    if IsHidden(mItem) then
      Inc(Result);
end;

function TAtlasDesignerHidden.HiddenClasses: TArray<string>;
begin
  Result := FClasses.Values.ToArray;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      Result := CompareText(ALeft, ARight);
      if Result = 0 then
        Result := CompareStr(ALeft, ARight);
    end));
end;

end.
