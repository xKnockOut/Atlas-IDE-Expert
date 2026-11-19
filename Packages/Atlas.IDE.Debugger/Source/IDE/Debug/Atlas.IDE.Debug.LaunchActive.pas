unit Atlas.IDE.Debug.LaunchActive;

// Aktiver Startverbund (#867) je Projektgruppe, persönlich gespeichert in
// %LOCALAPPDATA%\Atlas\debug-launchgroups.json. Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Debug.DialogCompletion;

type
  /// <summary>Aktiver Verbund je Projektgruppe, persönlich gespeichert.</summary>
  TAtlasIdeLaunchActive = class
  public const
    cFileName = 'debug-launchgroups.json';
  private class var
    FStore: TAtlasExpressionHistory;
    FKept: Boolean;
    class function Store: TAtlasExpressionHistory; static;
    class function GroupKey: string; static;
  public
    /// <summary>Name des aktiven Verbunds der Projektgruppe ('' = keiner).</summary>
    class function Name: string; static;
    class procedure SetName(const AName: string); static;
    class procedure Release; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Files.DataFile;

const
  cActiveWhat = 'debug launch groups';

function ActiveFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasIdeLaunchActive.cFileName);
end;

{ TAtlasIdeLaunchActive }

class function TAtlasIdeLaunchActive.Store: TAtlasExpressionHistory;
begin
  if FStore = nil then
  begin
    FStore := TAtlasExpressionHistory.Create(1);
    FKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(ActiveFile, cActiveWhat,
      function(const AText: string): Boolean
      begin
        Result := FStore.LoadFromText(AText);
      end));
  end;
  Result := FStore;
end;

class function TAtlasIdeLaunchActive.GroupKey: string;
var
  mModules: IOTAModuleServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.MainProjectGroup <> nil) then
  begin
    Result := mModules.MainProjectGroup.FileName;
  end;
end;

class function TAtlasIdeLaunchActive.Name: string;
var
  mItems: TArray<string>;
begin
  Result := '';
  mItems := Store.Items(GroupKey);
  if mItems <> nil then
  begin
    Result := mItems[0];
  end;
end;

class procedure TAtlasIdeLaunchActive.SetName(const AName: string);
var
  mChanged: Boolean;
begin
  if AName = '' then
  begin
    mChanged := Store.Remove(GroupKey, Name);
  end
  else
  begin
    mChanged := Store.Add(GroupKey, AName);
  end;
  if not mChanged or FKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(ActiveFile, FStore.ToText);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cActiveWhat, E);
  end;
end;

class procedure TAtlasIdeLaunchActive.Release;
begin
  FreeAndNil(FStore);
  FKept := False;
end;

end.
