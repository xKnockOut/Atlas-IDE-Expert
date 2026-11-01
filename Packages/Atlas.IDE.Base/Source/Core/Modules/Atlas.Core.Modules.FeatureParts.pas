unit Atlas.Core.Modules.FeatureParts;

// Teile der Feature-Tabelle als IAtlasFeaturePart (#1455): Ein Modul baut
// seine Teile aus Methodenreferenzen und stellt sie über seinen Scope bereit;
// Base (TAtlasModuleHosting) trägt sie in die Tabelle ein.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasFeaturePart = class(TInterfacedObject, IAtlasFeaturePart)
  private
    FName: string;
    FWanted: TAtlasFeatureWanted;
    FIsActive: TFunc<Boolean>;
    FStart: TProc;
    FStop: TProc;
    class function AtLevelWanted(AMinLevel: TAtlasSafeLevel): TAtlasFeatureWanted; static;
  public
    constructor Create(const AName: string; const AWanted: TAtlasFeatureWanted; const AIsActive: TFunc<Boolean>;
      const AStart, AStop: TProc);
    /// <summary>Teil, das ab Stufe AMinLevel läuft: Normal = nur normal, Safe = nicht minimal, Minimal = immer.
    /// Eigener Name statt Überladung (Delphi wählt zwischen Überladungen mit anonymen Methoden nicht, E2250).
    /// </summary>
    class function AtLevel(const AName: string; AMinLevel: TAtlasSafeLevel; const AIsActive: TFunc<Boolean>;
      const AStart, AStop: TProc): IAtlasFeaturePart; static;
    /// <summary>Teil nach AWanted.</summary>
    class function When(const AName: string; const AWanted: TAtlasFeatureWanted; const AIsActive: TFunc<Boolean>;
      const AStart, AStop: TProc): IAtlasFeaturePart; static;
    function Name: string;
    function Wanted(ALevel: TAtlasSafeLevel): Boolean;
    function IsActive: Boolean;
    procedure Start;
    procedure Stop;
  end;

implementation

{ TAtlasFeaturePart }

constructor TAtlasFeaturePart.Create(const AName: string; const AWanted: TAtlasFeatureWanted;
  const AIsActive: TFunc<Boolean>; const AStart, AStop: TProc);
begin
  inherited Create;
  FName := AName;
  FWanted := AWanted;
  FIsActive := AIsActive;
  FStart := AStart;
  FStop := AStop;
end;

class function TAtlasFeaturePart.AtLevelWanted(AMinLevel: TAtlasSafeLevel): TAtlasFeatureWanted;
begin
  Result :=
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := Ord(ALevel) <= Ord(AMinLevel);
    end;
end;

class function TAtlasFeaturePart.AtLevel(const AName: string; AMinLevel: TAtlasSafeLevel;
  const AIsActive: TFunc<Boolean>; const AStart, AStop: TProc): IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.Create(AName, AtLevelWanted(AMinLevel), AIsActive, AStart, AStop);
end;

class function TAtlasFeaturePart.When(const AName: string; const AWanted: TAtlasFeatureWanted;
  const AIsActive: TFunc<Boolean>; const AStart, AStop: TProc): IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.Create(AName, AWanted, AIsActive, AStart, AStop);
end;

function TAtlasFeaturePart.Name: string;
begin
  Result := FName;
end;

function TAtlasFeaturePart.Wanted(ALevel: TAtlasSafeLevel): Boolean;
begin
  Result := Assigned(FWanted) and FWanted(ALevel);
end;

function TAtlasFeaturePart.IsActive: Boolean;
begin
  Result := Assigned(FIsActive) and FIsActive();
end;

procedure TAtlasFeaturePart.Start;
begin
  if Assigned(FStart) then
    FStart();
end;

procedure TAtlasFeaturePart.Stop;
begin
  if Assigned(FStop) then
    FStop();
end;

end.
