unit Atlas.Core.Outline.LoadGuard;

// Schutz des Gliederungsstands während einer Abfrage (Zugriffsverletzung in
// AnsiLowerCase, 22.10.2026): Beim Laden holt der Stand die Sitzung, und das
// kann den Server starten oder die Projektkontexte abgleichen. Ändert sich
// dabei der Kontext, vergisst der Manager alle Stände, also auch den Eintrag,
// der gerade lädt; das Laden las danach freigegebenen Speicher. Auch das
// Warten auf documentSymbol arbeitet Nachrichten ab, und ein zweiter Takt
// konnte Einträge entfernen. Während einer Abfrage merkt sich der Wächter
// deshalb Entfernen und Leeren nur vor; nach der äußersten Abfrage gibt
// Leave zurück, was nachzuholen ist. Ohne VCL und Open Tools API.

interface

type
  TAtlasOutlineLoadGuard = class
  private
    FDepth: Integer;
    FClearAll: Boolean;
    FKeys: TArray<string>;
  public
    /// <summary>Eine Abfrage beginnt (verschachtelt erlaubt).</summary>
    procedure Enter;
    /// <summary>Eine Abfrage endet. True nur nach der äußersten Abfrage und wenn etwas nachzuholen ist:
    /// AClearAll = alle Stände vergessen, sonst die Schlüssel in AKeys.</summary>
    function Leave(out AClearAll: Boolean; out AKeys: TArray<string>): Boolean;
    /// <summary>Läuft gerade eine Abfrage?</summary>
    function Busy: Boolean;
    /// <summary>True: sofort leeren. False: vorgemerkt bis zum Ende der Abfrage.</summary>
    function ClearAll: Boolean;
    /// <summary>True: sofort entfernen. False: vorgemerkt bis zum Ende der Abfrage.</summary>
    function Remove(const AKey: string): Boolean;
  end;

implementation

{ TAtlasOutlineLoadGuard }

procedure TAtlasOutlineLoadGuard.Enter;
begin
  Inc(FDepth);
end;

function TAtlasOutlineLoadGuard.Leave(out AClearAll: Boolean; out AKeys: TArray<string>): Boolean;
begin
  AClearAll := False;
  AKeys := nil;
  if FDepth > 0 then
    Dec(FDepth);
  if FDepth > 0 then
    Exit(False);
  AClearAll := FClearAll;
  if not AClearAll then
    AKeys := FKeys;
  FClearAll := False;
  FKeys := nil;
  Result := AClearAll or (Length(AKeys) > 0);
end;

function TAtlasOutlineLoadGuard.Busy: Boolean;
begin
  Result := FDepth > 0;
end;

function TAtlasOutlineLoadGuard.ClearAll: Boolean;
begin
  Result := FDepth = 0;
  if Result then
    Exit;
  FClearAll := True;
  FKeys := nil;
end;

function TAtlasOutlineLoadGuard.Remove(const AKey: string): Boolean;
var
  Existing: string;
begin
  Result := FDepth = 0;
  if Result or FClearAll then
    Exit;
  for Existing in FKeys do
    if Existing = AKey then
      Exit;
  FKeys := FKeys + [AKey];
end;

end.
