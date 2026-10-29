unit Ref.Sprache.Merkmale; // ERWARTET-PROJEKT: unused-unit

// Sprachmerkmale für Navigation, Hover und Prüfregeln.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  IFormatierer = interface
    ['{6F1C2B9E-4A37-4D2B-9E61-3C5A7B8D9E01}']
    function Formatieren(const AWert: Integer): string;
  end;

  TDezimalFormatierer = class(TInterfacedObject, IFormatierer) // ERWARTET-PROJEKT: unused-public-member
  public
    function Formatieren(const AWert: Integer): string;
  end;

  TStapel<T> = class // ERWARTET-PROJEKT: unused-public-member
  private
    FElemente: TList<T>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Ablegen(const AElement: T); // ERWARTET-PROJEKT: unused-public-member
    function Entnehmen: T; // ERWARTET-PROJEKT: unused-public-member
    function Anzahl: Integer; // ERWARTET-PROJEKT: unused-public-member
  end;

  TPaar<TSchluessel, TWert> = record // ERWARTET-PROJEKT: unused-public-member
    Schluessel: TSchluessel;
    Wert: TWert;
    constructor Create(const ASchluessel: TSchluessel; const AWert: TWert);
  end;

  TStringHelfer = record helper for string
    function IstLeer: Boolean;
  end;

  TZaehlerFunktion = reference to function(const AText: string): Integer;

  /// <summary>Markiert Klassen, die ein Plugin per RTTI aufruft. Der Test des Referenzprojekts setzt
  /// deadCode.keepAttributes auf Schnittstelle (#64).</summary>
  SchnittstelleAttribute = class(TCustomAttribute)
  end;

  [Schnittstelle]
  TPluginAufruf = class
  public
    procedure Melden; // KEIN-TREFFER: unused-public-member
  end;

function Plattform: string; // ERWARTET-PROJEKT: unused-public-member
function SummeQuadrate(const AWerte: TArray<Integer>): Integer; // ERWARTET-PROJEKT: unused-public-member
function Zaehler: TZaehlerFunktion; // ERWARTET-PROJEKT: unused-public-member

implementation

{ TDezimalFormatierer }

function TDezimalFormatierer.Formatieren(const AWert: Integer): string;
begin
  Result := IntToStr(AWert);
end;

{ TStapel<T> }

constructor TStapel<T>.Create;
begin
  inherited Create;
  FElemente := TList<T>.Create;
end;

destructor TStapel<T>.Destroy;
begin
  FElemente.Free;
  inherited;
end;

procedure TStapel<T>.Ablegen(const AElement: T);
begin
  FElemente.Add(AElement);
end;

function TStapel<T>.Entnehmen: T;
begin
  Result := FElemente.Last;
  FElemente.Delete(FElemente.Count - 1);
end;

function TStapel<T>.Anzahl: Integer;
begin
  Result := FElemente.Count;
end;

{ TPaar<TSchluessel, TWert> }

constructor TPaar<TSchluessel, TWert>.Create(const ASchluessel: TSchluessel; const AWert: TWert);
begin
  Schluessel := ASchluessel;
  Wert := AWert;
end;

{ TPluginAufruf }

procedure TPluginAufruf.Melden;
begin
end;

{ TStringHelfer }

function TStringHelfer.IstLeer: Boolean;
begin
  Result := Self = '';
end;

function Plattform: string;
begin
{$IFDEF WIN64}
  Result := 'Win64';
{$ELSE}
  {$IFDEF WIN32}
  Result := 'Win32';
  {$ELSE}
  Result := 'Andere';
  {$ENDIF}
{$ENDIF}
end;

function SummeQuadrate(const AWerte: TArray<Integer>): Integer;
begin
  Result := 0;
  for var Wert in AWerte do
  begin
    const Quadrat = Wert * Wert;
    Inc(Result, Quadrat);
  end;
end;

function Zaehler: TZaehlerFunktion;
begin
  Result :=
    function(const AText: string): Integer
    begin
      Result := Length(AText);
    end;
end;

end.
