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
    class function FromJson(const AValue: TJSONValue; const AUriToPath: TFunc<string, string>): TAtlasTestUnitInfo;
      static;
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
  mAnswer: TJSONObject;
  mUri: string;
begin
  Result := Default(TAtlasTestUnitInfo);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mAnswer := TJSONObject(AValue);
  mAnswer.TryGetValue<string>('unit', Result.UnitName);
  mAnswer.TryGetValue<Boolean>('isTest', Result.IsTest);
  mAnswer.TryGetValue<string>('counterpart', Result.Counterpart);
  // "uri" ist null, wenn das Gegenstück fehlt.
  if (mAnswer.GetValue('uri') is TJSONString) and mAnswer.TryGetValue<string>('uri', mUri) and (mUri <> '') then
  begin
    Result.CounterpartFile := AUriToPath(mUri);
  end;
  mAnswer.TryGetValue<Boolean>('canCreate', Result.CanCreate);
  if mAnswer.TryGetValue<string>('newUri', mUri) and (mUri <> '') then
  begin
    Result.NewFile := AUriToPath(mUri);
  end;
  mAnswer.TryGetValue<string>('reason', Result.Reason);
end;

function TAtlasTestUnitInfo.Lens: TAtlasTestUnitLens;
begin
  if UnitName = '' then
  begin
    Result := TAtlasTestUnitLens.None;
  end
  else if CounterpartFile <> '' then
  begin
    if IsTest then
    begin
      Result := TAtlasTestUnitLens.ToUnit;
    end
    else
    begin
      Result := TAtlasTestUnitLens.ToTest;
    end;
  end
  else if CanCreate then
  begin
    Result := TAtlasTestUnitLens.CreateTest;
  end
  else
  begin
    Result := TAtlasTestUnitLens.None;
  end;
end;

{ TAtlasTestUnits }

/// <summary>Zeile ALine (getrimmt) gehört zu einem Kommentar oder ist leer; führt AInComment für mehrzeilige
/// Kommentare vor dem Kopf nach.</summary>
function IsSkipped(const ALine: string; var AInComment: Boolean): Boolean;
begin
  Result := True;
  if AInComment then
  begin
    AInComment := (Pos('}', ALine) = 0) and (Pos('*)', ALine) = 0);
  end
  else if (ALine.StartsWith('{') and (Pos('}', ALine) = 0)) or (ALine.StartsWith('(*') and (Pos('*)', ALine) = 0)) then
  begin
    AInComment := True;
  end
  else
  begin
    Result := (ALine = '') or ALine.StartsWith('//') or ALine.StartsWith('{') or ALine.StartsWith('(*');
  end;
end;

class function TAtlasTestUnits.UnitLine(const ALines: TArray<string>): Integer;
var
  mIndex: Integer;
  mLine: string;
  mInComment, mDone: Boolean;
begin
  Result := -1;
  mInComment := False;
  mDone := False;
  mIndex := 0;
  while not mDone and (mIndex <= High(ALines)) do
  begin
    mLine := Trim(ALines[mIndex]);
    if not IsSkipped(mLine, mInComment) then
    begin
      // Erstes echtes Wort ist nicht "unit": Programm, Package oder anderes.
      mDone := True;
      if SameText(Copy(mLine, 1, 5), 'unit ') or SameText(mLine, 'unit') then
      begin
        Result := mIndex;
      end;
    end;
    Inc(mIndex);
  end;
end;

end.
