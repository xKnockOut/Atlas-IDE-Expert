unit Atlas.IDE.Tasks.Shortcuts;

// Tasten und Statuszeilen der Projektaufgaben (#900): je Aufgabe mit key eine
// Tastenbindung (Konflikte meldet TAtlasIdeKeyBinding) und je Aufgabe eine
// Statuszeile mit dem letzten Lauf; ein Klick darauf startet sie. Der Läufer
// (Atlas.IDE.Tasks.Runner) legt beide nach jedem Neuladen neu an und meldet
// den Text der Zeilen. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Tasks.Definitions,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Tasks.Projects;

type
  TAtlasIdeTaskShortcuts = class
  private
    FKeys: TObjectList<TAtlasIdeKeyBinding>;
    FStatus: TArray<TAtlasStatusLine>;
    FStatusRefs: TArray<IAtlasStatusItem>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Tasten und Statuszeilen entfernen.</summary>
    procedure Clear;
    /// <summary>Tasten und Statuszeilen für ATasks neu anlegen. ARun startet eine Aufgabe; AAlive sagt, ob der
    /// Läufer noch lebt (Klick auf eine Statuszeile).</summary>
    procedure Rebuild(const ATasks: TAtlasTaskDefinitions; const ARun: TAtlasTaskRunByName;
      const AAlive: TFunc<Boolean>);
    /// <summary>Statuszeile der Aufgabe AName: Text, Zustand und Kurzfassung ABrief.</summary>
    procedure Update(const AName, AText: string; AState: TAtlasStatusState; const ABrief: string);
    class function StatusId(const AName: string): string; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Build.Strings;

const
  cStatusOrder = 40;

/// <summary>ARun mit AName; ein Grund für „nicht gestartet“ erscheint in der Meldungsansicht.</summary>
procedure RunOrSay(const ARun: TAtlasTaskRunByName; const AName: string);
var
  mReason: string;
begin
  if not ARun(AName, mReason) and (mReason <> '') then
  begin
    TAtlasIdeTaskProjects.Say(mReason, True);
  end;
end;

function KeyAction(const ARun: TAtlasTaskRunByName; const AName: string): TProc;
begin
  Result :=
    procedure
    begin
      RunOrSay(ARun, AName);
    end;
end;

function StatusAction(const ARun: TAtlasTaskRunByName; const AAlive: TFunc<Boolean>; const AName: string): TProc;
begin
  Result :=
    procedure
    begin
      if not AAlive() then
      begin
        Exit;
      end;
      TAtlasGuard.Run(TAtlasFeature.Tasks,
        procedure
        begin
          RunOrSay(ARun, AName);
        end);
    end;
end;

{ TAtlasIdeTaskShortcuts }

constructor TAtlasIdeTaskShortcuts.Create;
begin
  inherited Create;
  FKeys := TObjectList<TAtlasIdeKeyBinding>.Create(True);
end;

destructor TAtlasIdeTaskShortcuts.Destroy;
begin
  Clear;
  FreeAndNil(FKeys);
  inherited Destroy;
end;

class function TAtlasIdeTaskShortcuts.StatusId(const AName: string): string;
begin
  Result := 'atlas.task.' + AnsiLowerCase(AName);
end;

procedure TAtlasIdeTaskShortcuts.Clear;
var
  mLine: TAtlasStatusLine;
begin
  if FKeys <> nil then
  begin
    FKeys.Clear;
  end;
  for mLine in FStatus do
  begin
    mLine.Detach;
    TAtlasStatusRegistry.Default.Remove(mLine.Id);
  end;
  FStatus := nil;
  FStatusRefs := nil;
end;

procedure TAtlasIdeTaskShortcuts.Rebuild(const ATasks: TAtlasTaskDefinitions; const ARun: TAtlasTaskRunByName;
  const AAlive: TFunc<Boolean>);
var
  mIndex: Integer;
  mTask: TAtlasTaskDefinition;
  mBinding: TAtlasIdeKeyBinding;
  mLine: TAtlasStatusLine;
begin
  Clear;
  for mIndex := 0 to High(ATasks) do
  begin
    mTask := ATasks[mIndex];
    if mTask.Key <> 0 then
    begin
      mBinding := TAtlasIdeKeyBinding.Create('Atlas.Task' + IntToStr(mIndex),
        TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksKeyWhat, [mTask.Name]), TAtlasFeature.Tasks,
        KeyAction(ARun, mTask.Name));
      FKeys.Add(mBinding);
      mBinding.Rebind(mTask.Key, False, TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksKeyWhat, [mTask.Name]));
    end;
    mLine := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, StatusId(mTask.Name), cStatusOrder + mIndex,
      StatusAction(ARun, AAlive, mTask.Name));
    FStatus := FStatus + [mLine];
    FStatusRefs := FStatusRefs + [mLine as IAtlasStatusItem];
    TAtlasStatusRegistry.Default.Add(mLine);
  end;
end;

procedure TAtlasIdeTaskShortcuts.Update(const AName, AText: string; AState: TAtlasStatusState; const ABrief: string);
var
  mLine: TAtlasStatusLine;
begin
  for mLine in FStatus do
  begin
    if SameText(mLine.Id, StatusId(AName)) then
    begin
      mLine.Update(AText, AState, '', AName, ABrief);
    end;
  end;
end;

end.
