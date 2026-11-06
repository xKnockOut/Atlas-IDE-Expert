unit Atlas.Common.Rules.Registry;

// Verzeichnis der Prüfregeln. Jede Kennung darf nur einmal vorkommen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Contract;

type
  ERuleRegistry = class(Exception);

  TRuleRegistry = class
  private
    FRules: TList<IRule>;
    /// <summary>Regeln nach Kennung in Großbuchstaben: Die Prüfung auf doppelte Kennungen las sonst je Anmeldung
    /// den Deskriptor jeder schon angemeldeten Regel (quadratisch, je Anfrage im Server).</summary>
    FById: TDictionary<string, IRule>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Nimmt ARule auf; ERuleRegistry bei leerer oder doppelter Kennung.</summary>
    /// <remarks>ARule ohne const: Aufrufer übergeben TXyzRule.Create direkt;
    /// so gibt die Referenzzählung die Regel auch bei einer Ausnahme frei.</remarks>
    procedure Register(ARule: IRule);
    function Find(const AId: string; out ARule: IRule): Boolean;
    /// <summary>Alle Regeln in Reihenfolge der Registrierung.</summary>
    function Rules: TArray<IRule>;
  end;

implementation


uses
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TRegistryText = (NoId, Duplicate);

const
  cTexts: array[TRegistryText] of TAtlasText = (
    (De: 'Regel ohne Kennung'; En: 'Rule without id'),
    (De: 'Regel "%s" ist bereits registriert'; En: 'Rule "%s" is already registered'));

{$SCOPEDENUMS OFF}
{ TRuleRegistry }

constructor TRuleRegistry.Create;
begin
  inherited Create;
  FRules := TList<IRule>.Create;
  FById := TDictionary<string, IRule>.Create;
end;

destructor TRuleRegistry.Destroy;
begin
  FById.Free;
  FRules.Free;
  inherited;
end;

procedure TRuleRegistry.Register(ARule: IRule);
var
  Id: string;
  Existing: IRule;
begin
  Id := ARule.Descriptor.Id;
  if Id = '' then
  begin
    raise ERuleRegistry.Create(cTexts[TRegistryText.NoId].Text);
  end;
  if Find(Id, Existing) then
  begin
    raise ERuleRegistry.CreateFmt(cTexts[TRegistryText.Duplicate].Text, [Id]);
  end;
  FRules.Add(ARule);
  FById.Add(UpperCase(Id), ARule);
end;

function TRuleRegistry.Find(const AId: string; out ARule: IRule): Boolean;
begin
  Result := FById.TryGetValue(UpperCase(AId), ARule);
  if not Result then
  begin
    ARule := nil;
  end;
end;

function TRuleRegistry.Rules: TArray<IRule>;
begin
  Result := FRules.ToArray;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Registry', cTexts);

end.
