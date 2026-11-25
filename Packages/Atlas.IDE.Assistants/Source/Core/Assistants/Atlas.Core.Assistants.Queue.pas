unit Atlas.Core.Assistants.Queue;

// Warteschlange von Aufträgen der KI-Assistenten mit Kennung, ohne Windows und VCL: wartende Änderungen (#2605) und
// offene Fragen (#2620). Die Einträge stehen in der Reihenfolge ihres Eingangs; die Ableitung sagt mit KeyOf, welche
// Kennung ein Eintrag hat, und ergänzt, was nur sie braucht (nächste Frage, Änderungen je Datei). Nicht threadsicher:
// Beide Besitzer leben im Hauptthread des Plugins.

interface

uses
  System.Generics.Collections,
  System.Generics.Defaults;

type
  TAtlasAssistantsQueue<TItem, TKey> = class
  protected
    FItems: TList<TItem>;
    function KeyOf(const AItem: TItem): TKey; virtual; abstract;
    /// <summary>Stelle des Eintrags mit der Kennung AKey; -1 ohne.</summary>
    function IndexOf(const AKey: TKey): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;
    /// <summary>Eintrag mit der Kennung AKey; ohne ihn False und AItem = Default(TItem).</summary>
    function TryGet(const AKey: TKey; out AItem: TItem): Boolean;
    /// <summary>Entfernt den Eintrag AKey; False, wenn es ihn nicht (mehr) gibt.</summary>
    function Remove(const AKey: TKey): Boolean;
  end;

implementation

{ TAtlasAssistantsQueue<TItem, TKey> }

constructor TAtlasAssistantsQueue<TItem, TKey>.Create;
begin
  inherited Create;
  FItems := TList<TItem>.Create;
end;

destructor TAtlasAssistantsQueue<TItem, TKey>.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TAtlasAssistantsQueue<TItem, TKey>.IndexOf(const AKey: TKey): Integer;
var
  mComparer: IEqualityComparer<TKey>;
  mIndex: Integer;
begin
  mComparer := TEqualityComparer<TKey>.Default;
  for mIndex := 0 to FItems.Count - 1 do
  begin
    if mComparer.Equals(KeyOf(FItems[mIndex]), AKey) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasAssistantsQueue<TItem, TKey>.Count: Integer;
begin
  Result := FItems.Count;
end;

function TAtlasAssistantsQueue<TItem, TKey>.TryGet(const AKey: TKey; out AItem: TItem): Boolean;
var
  mIndex: Integer;
begin
  AItem := Default(TItem);
  mIndex := IndexOf(AKey);
  Result := mIndex >= 0;
  if Result then
  begin
    AItem := FItems[mIndex];
  end;
end;

function TAtlasAssistantsQueue<TItem, TKey>.Remove(const AKey: TKey): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AKey);
  Result := mIndex >= 0;
  if Result then
  begin
    FItems.Delete(mIndex);
  end;
end;

end.
