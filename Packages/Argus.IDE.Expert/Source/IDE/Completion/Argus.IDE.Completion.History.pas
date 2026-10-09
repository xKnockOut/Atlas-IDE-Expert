unit Argus.IDE.Completion.History;

// Verlauf der lernenden Gewichtung (#418) für die IDE: eine Instanz für das
// ganze Plugin, gelesen aus %APPDATA%\Argus\usage.json beim ersten Zugriff,
// gespeichert alle paar Übernahmen und beim Entladen. „Verlauf zurücksetzen“
// auf der Optionsseite leert ihn sofort.

interface

uses
  Argus.Core.Completion.Usage;

type
  TArgusIdeHistory = class
  private class var
    FUsage: TArgusUsage;
    FCommits: Integer;
  public
    class function FileName: string; static;
    class function Instance: TArgusUsage; static;
    /// <summary>Nach einer Übernahme: alle 10 Übernahmen speichern.</summary>
    class procedure Committed; static;
    class procedure Save; static;
    class procedure Reset; static;
    class procedure Release; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils;

{ TArgusIdeHistory }

class function TArgusIdeHistory.FileName: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'Argus'), 'usage.json');
end;

class function TArgusIdeHistory.Instance: TArgusUsage;
begin
  if FUsage = nil then
  begin
    FUsage := TArgusUsage.Create;
    try
      FUsage.LoadFromFile(FileName);
    except
      // Unlesbarer Verlauf: leer beginnen.
      on Exception do
        FUsage.Clear;
    end;
  end;
  Result := FUsage;
end;

class procedure TArgusIdeHistory.Committed;
begin
  Inc(FCommits);
  if FCommits mod 10 = 0 then
    Save;
end;

class procedure TArgusIdeHistory.Save;
begin
  if (FUsage = nil) or not FUsage.Changed then
    Exit;
  try
    FUsage.SaveToFile(FileName);
  except
    // Speichern darf die IDE nie stören.
    on Exception do
      ;
  end;
end;

class procedure TArgusIdeHistory.Reset;
begin
  Instance.Clear;
  Save;
end;

class procedure TArgusIdeHistory.Release;
begin
  Save;
  FreeAndNil(FUsage);
end;

end.
