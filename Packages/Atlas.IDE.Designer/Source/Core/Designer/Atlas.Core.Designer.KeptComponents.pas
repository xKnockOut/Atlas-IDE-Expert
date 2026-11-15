unit Atlas.Core.Designer.KeptComponents;

// Gemerkte Komponenten eines Formulars über einen modalen Dialog oder einen
// Zug mit der Maus hinweg, ohne VCL und Windows. Während ein Dialog offen ist
// oder die Maus gezogen wird, laufen Takte und eingereihte Aufrufe weiter;
// lädt dabei etwas das Formular neu (Datei-Neulader, Versionsverwaltung,
// MCP-Auftrag) oder löscht eine Komponente, zeigen gemerkte Verweise auf
// freigegebene Objekte.
// - Take merkt Formular und Komponenten als Zeiger mit Namen.
// - Alive prüft am aktuellen Formular, ob es dasselbe ist und jede gemerkte
//   Komponente noch darin lebt (über Components erreichbar, gleicher Zeiger,
//   gleicher Name). Die gemerkten Zeiger werden dabei nie dereferenziert,
//   nur mit lebenden Komponenten verglichen.
// - SameAs vergleicht zwei Merkzettel (dieselbe Gruppe vor und nach einem
//   Dialog), ebenfalls nur über Zeiger und Namen.
// - Reachable sagt vorab, ob eine Komponente sich so prüfen lässt; was nicht
//   über Components erreichbar ist, merkt sich ein Werkzeug besser nicht.

interface

uses
  System.Classes;

type
  /// <summary>Formular und gemerkte Komponenten; Prüfung ohne Zugriff auf die gemerkten Objekte.</summary>
  TAtlasKeptComponents = record
  private
    FRoot: Pointer;
    FRootName: string;
    FItems: TArray<Pointer>;
    FNames: TArray<string>;
  public
    /// <summary>Formular ARoot merken, noch ohne Komponenten.</summary>
    class function Take(ARoot: TComponent): TAtlasKeptComponents; static;
    /// <summary>Komponente AItem dazu merken (nil wird übergangen).</summary>
    procedure Add(AItem: TComponent);
    /// <summary>True, wenn ARoot das gemerkte Formular ist und jede gemerkte Komponente noch darin lebt.</summary>
    function Alive(ARoot: TComponent): Boolean;
    /// <summary>True, wenn AItem ARoot selbst ist oder über Components (auch verschachtelt) daran hängt.</summary>
    class function Reachable(ARoot, AItem: TComponent): Boolean; static;
    /// <summary>True, wenn AOther dasselbe Formular mit denselben Komponenten in derselben Reihenfolge merkt.
    /// </summary>
    function SameAs(const AOther: TAtlasKeptComponents): Boolean;
    /// <summary>Anzahl der gemerkten Komponenten (ohne Formular).</summary>
    function Count: Integer;
  end;

implementation

uses
  System.SysUtils;

/// <summary>Lebt unter AOwner eine Komponente mit Zeiger AItem? AName: ihr Name, wenn ja.</summary>
function FindBelow(AOwner: TComponent; AItem: Pointer; out AName: string): Boolean;
var
  mIndex: Integer;
  mChild: TComponent;
begin
  for mIndex := 0 to AOwner.ComponentCount - 1 do
  begin
    mChild := AOwner.Components[mIndex];
    if Pointer(mChild) = AItem then
    begin
      AName := mChild.Name;
      Exit(True);
    end;
    if FindBelow(mChild, AItem, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasKeptComponents.Take(ARoot: TComponent): TAtlasKeptComponents;
begin
  Result := Default(TAtlasKeptComponents);
  Result.FRoot := ARoot;
  if ARoot <> nil then
  begin
    Result.FRootName := ARoot.Name;
  end;
end;

procedure TAtlasKeptComponents.Add(AItem: TComponent);
begin
  if AItem = nil then
  begin
    Exit;
  end;
  FItems := FItems + [Pointer(AItem)];
  FNames := FNames + [AItem.Name];
end;

function TAtlasKeptComponents.Count: Integer;
begin
  Result := Length(FItems);
end;

function TAtlasKeptComponents.Alive(ARoot: TComponent): Boolean;
var
  mIndex: Integer;
  mName: string;
begin
  if (ARoot = nil) or (Pointer(ARoot) <> FRoot) or not SameText(ARoot.Name, FRootName) then
  begin
    Exit(False);
  end;
  for mIndex := 0 to High(FItems) do
  begin
    if FItems[mIndex] = FRoot then
    begin
      Continue;
    end;
    if not FindBelow(ARoot, FItems[mIndex], mName) or not SameText(mName, FNames[mIndex]) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TAtlasKeptComponents.SameAs(const AOther: TAtlasKeptComponents): Boolean;
var
  mIndex: Integer;
begin
  Result := (FRoot = AOther.FRoot) and SameText(FRootName, AOther.FRootName) and
    (Length(FItems) = Length(AOther.FItems));
  for mIndex := 0 to High(FItems) do
  begin
    Result := Result and (FItems[mIndex] = AOther.FItems[mIndex]) and SameText(FNames[mIndex], AOther.FNames[mIndex]);
  end;
end;

class function TAtlasKeptComponents.Reachable(ARoot, AItem: TComponent): Boolean;
var
  mName: string;
begin
  Result := (ARoot <> nil) and (AItem <> nil) and ((AItem = ARoot) or FindBelow(ARoot, AItem, mName));
end;

end.
