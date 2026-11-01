unit Atlas.Core.Editor.TestUnit;

// Zwischen Unit und Testunit wechseln (#189): Antwort des Servers auf
// atlas.server.testUnit lesen, Zeile „unit …;“ für die Code Lens finden und
// ihren Text wählen. Ohne VCL und OTA; Anfrage, Öffnen und Zeichnen macht die
// IDE-Schicht.

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  /// <summary>Was die Code Lens anbietet.</summary>
  TAtlasTestUnitLens = (None, ToTest, ToUnit, CreateTest);
{$SCOPEDENUMS OFF}

  TAtlasTestUnitInfo = record
    /// <summary>Name der Unit; '' wenn die Datei keine Unit ist.</summary>
    UnitName: string;
    IsTest: Boolean;
    /// <summary>Name des Gegenstücks (Testunit bzw. getestete Unit).</summary>
    Counterpart: string;
    /// <summary>Datei des Gegenstücks; '' wenn es fehlt.</summary>
    CounterpartFile: string;
    CanCreate: Boolean;
    /// <summary>Datei einer neu anzulegenden Testunit.</summary>
    NewFile: string;
    /// <summary>Warum es kein Gegenstück gibt; sonst ''.</summary>
    Reason: string;
    /// <summary>Aus der Antwort; AUriToPath macht aus URIs Dateinamen.</summary>
    class function FromJson(const AValue: TJSONValue; const AUriToPath: TFunc<string, string>): TAtlasTestUnitInfo; static;
    /// <summary>Was die Code Lens zeigt.</summary>
    function Lens: TAtlasTestUnitLens;
  end;

  TAtlasTestUnits = class
  public
    /// <summary>Zeile (0-basiert) mit „unit Name;“; -1 wenn keine.</summary>
    class function UnitLine(const ALines: TArray<string>): Integer; static;
  end;

implementation

{ TAtlasTestUnitInfo }

class function TAtlasTestUnitInfo.FromJson(const AValue: TJSONValue;
  const AUriToPath: TFunc<string, string>): TAtlasTestUnitInfo;
var
  Answer: TJSONObject;
  Uri: string;
begin
  Result := Default(TAtlasTestUnitInfo);
  if not (AValue is TJSONObject) then
    Exit;
  Answer := TJSONObject(AValue);
  Answer.TryGetValue<string>('unit', Result.UnitName);
  Answer.TryGetValue<Boolean>('isTest', Result.IsTest);
  Answer.TryGetValue<string>('counterpart', Result.Counterpart);
  // "uri" ist null, wenn das Gegenstück fehlt.
  if (Answer.GetValue('uri') is TJSONString) and Answer.TryGetValue<string>('uri', Uri) and (Uri <> '') then
    Result.CounterpartFile := AUriToPath(Uri);
  Answer.TryGetValue<Boolean>('canCreate', Result.CanCreate);
  if Answer.TryGetValue<string>('newUri', Uri) and (Uri <> '') then
    Result.NewFile := AUriToPath(Uri);
  Answer.TryGetValue<string>('reason', Result.Reason);
end;

function TAtlasTestUnitInfo.Lens: TAtlasTestUnitLens;
begin
  if UnitName = '' then
    Result := TAtlasTestUnitLens.None
  else if CounterpartFile <> '' then
  begin
    if IsTest then
      Result := TAtlasTestUnitLens.ToUnit
    else
      Result := TAtlasTestUnitLens.ToTest;
  end
  else if CanCreate then
    Result := TAtlasTestUnitLens.CreateTest
  else
    Result := TAtlasTestUnitLens.None;
end;

{ TAtlasTestUnits }

class function TAtlasTestUnits.UnitLine(const ALines: TArray<string>): Integer;
var
  Index: Integer;
  Line: string;
  InComment: Boolean;
begin
  InComment := False;
  for Index := 0 to High(ALines) do
  begin
    Line := Trim(ALines[Index]);
    // Mehrzeilige Kommentare vor dem Kopf überspringen.
    if InComment then
    begin
      if (Pos('}', Line) > 0) or (Pos('*)', Line) > 0) then
        InComment := False;
      Continue;
    end;
    if Line.StartsWith('{') and (Pos('}', Line) = 0) then
    begin
      InComment := True;
      Continue;
    end;
    if Line.StartsWith('(*') and (Pos('*)', Line) = 0) then
    begin
      InComment := True;
      Continue;
    end;
    if (Line = '') or Line.StartsWith('//') or Line.StartsWith('{') or Line.StartsWith('(*') then
      Continue;
    if SameText(Copy(Line, 1, 5), 'unit ') or SameText(Line, 'unit') then
      Exit(Index);
    // Erstes echtes Wort ist nicht "unit": Programm, Package oder anderes.
    Exit(-1);
  end;
  Result := -1;
end;

end.
