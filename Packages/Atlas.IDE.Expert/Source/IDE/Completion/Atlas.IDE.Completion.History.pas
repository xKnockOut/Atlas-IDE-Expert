unit Atlas.IDE.Completion.History;

// Verlauf der lernenden Gewichtung (#418) für die IDE: eine Instanz für das
// ganze Plugin, gelesen aus %APPDATA%\Atlas\usage.json beim ersten Zugriff,
// gespeichert alle paar Übernahmen und beim Entladen. „Verlauf zurücksetzen“
// auf der Optionsseite leert ihn sofort.

interface

uses
  Atlas.Core.Completion.Usage;

type
  TAtlasIdeHistory = class
  private class var
    FUsage: TAtlasUsage;
    FCommits: Integer;
  public
    class function FileName: string; static;
    class function Instance: TAtlasUsage; static;
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

{ TAtlasIdeHistory }

class function TAtlasIdeHistory.FileName: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'Atlas'), 'usage.json');
end;

class function TAtlasIdeHistory.Instance: TAtlasUsage;
begin
  if FUsage = nil then
  begin
    FUsage := TAtlasUsage.Create;
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

class procedure TAtlasIdeHistory.Committed;
begin
  Inc(FCommits);
  if FCommits mod 10 = 0 then
    Save;
end;

class procedure TAtlasIdeHistory.Save;
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

class procedure TAtlasIdeHistory.Reset;
begin
  Instance.Clear;
  Save;
end;

class procedure TAtlasIdeHistory.Release;
begin
  Save;
  FreeAndNil(FUsage);
end;

end.
