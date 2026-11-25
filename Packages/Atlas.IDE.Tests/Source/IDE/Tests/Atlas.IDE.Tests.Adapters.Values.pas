unit Atlas.IDE.Tests.Adapters.Values;

// Erwartet und erhalten eines Fehlschlags für Base und die Willkommensseite (#1779): TAtlasTestsValues erfüllt
// IAtlasTestValues (Atlas.IDE.Base.Foundation.Tests) für „Vergleichen“ im Befund-Hover und auf der Kachel
// „Testergebnisse“. Den Vergleich des letzten Laufs liefert die Composition (Atlas.IDE.Tests.Composition) über
// ACompare; nil, solange der Teil Tests nicht läuft.

interface

uses
  System.SysUtils,
  Atlas.IDE.Base.Foundation.Tests,
  Atlas.IDE.Tests.Compare;

type
  TAtlasTestsValues = class(TInterfacedObject, IAtlasTestValues)
  private
    FCompare: TFunc<TAtlasIdeTestCompare>;
  public
    constructor Create(const ACompare: TFunc<TAtlasIdeTestCompare>);
    function HasValuesAt(ALine: Integer): Boolean;
    procedure CompareAt(ALine: Integer);
    function HasValues(const AFullName: string): Boolean;
    procedure Compare(const AFullName: string);
  end;

implementation

{ TAtlasTestsValues }

constructor TAtlasTestsValues.Create(const ACompare: TFunc<TAtlasIdeTestCompare>);
begin
  inherited Create;
  FCompare := ACompare;
end;

function TAtlasTestsValues.HasValuesAt(ALine: Integer): Boolean;
var
  mCompare: TAtlasIdeTestCompare;
begin
  mCompare := FCompare();
  Result := (mCompare <> nil) and mCompare.HasValuesAt(ALine);
end;

procedure TAtlasTestsValues.CompareAt(ALine: Integer);
var
  mCompare: TAtlasIdeTestCompare;
begin
  mCompare := FCompare();
  if mCompare <> nil then
  begin
    mCompare.CompareAt(ALine);
  end;
end;

function TAtlasTestsValues.HasValues(const AFullName: string): Boolean;
var
  mCompare: TAtlasIdeTestCompare;
begin
  mCompare := FCompare();
  Result := (mCompare <> nil) and mCompare.HasValues(AFullName);
end;

procedure TAtlasTestsValues.Compare(const AFullName: string);
var
  mCompare: TAtlasIdeTestCompare;
begin
  mCompare := FCompare();
  if mCompare <> nil then
  begin
    mCompare.CompareTest(AFullName);
  end;
end;

end.
