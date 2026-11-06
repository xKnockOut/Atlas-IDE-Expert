unit Atlas.IDE.CodeInsight.IdeTypes;

// Sammelt die Typen der geladenen Packages für atlas/ideTypes (Hauptthread, beim Start der Sitzung). Zwei Quellen:
// - die RTTI jedes geladenen Packages (TRttiContext.GetPackages): alle öffentlichen Typen samt Unit, bei Klassen
//   mit Vorfahr; so kennt die IDE auch Typen aus Packages, die nur als BPL/DCP/DCU installiert sind;
// - die Komponenten der Palette (IOTAPackageServices, über RegisterComponents angemeldet) über GetClass.
// Packages der Installation (RTL, VCL, FMX; ihr Quelltext liegt bei) und die von Atlas selbst bleiben außen vor:
// Sie stehen schon im Index bzw. gehören nicht in fremde Projekte.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Lsp.IdeTypes;

type
  TAtlasIdeTypeCollector = class
  private
    /// <summary>Typen der Packages an ATypes anhängen; Ergebnis: Zahl der Packages, deren RTTI nicht lesbar war.
    /// </summary>
    class function AddPackages(const ASkipped: TArray<string>; ATypes: TList<TAtlasIdeType>): Integer; static;
    class procedure AddPalette(const ASkipped: TArray<string>; ATypes: TList<TAtlasIdeType>); static;
  public
    /// <summary>Ordner, deren Packages nicht zählen: Installation und Atlas.</summary>
    class function SkippedFolders: TArray<string>; static;
    /// <summary>Typen der geladenen Packages außerhalb der Installation; nur im Hauptthread. AFailed: Packages,
    /// deren RTTI nicht lesbar war (sie fehlen im Ergebnis).</summary>
    class function Collect(out AFailed: Integer): TArray<TAtlasIdeType>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  ToolsAPI,
  Atlas.IDE.Foundation.Host;

class function TAtlasIdeTypeCollector.SkippedFolders: TArray<string>;
begin
  // bds.exe liegt in <Installation>\bin; Base und seine Module liegen im Ordner von Base.
  Result := TArray<string>.Create(ExtractFileDir(ExtractFileDir(ParamStr(0))),
    ExcludeTrailingPathDelimiter(TAtlasIdeHost.InstallFolder));
end;

/// <summary>Qualifizierter Name des Vorfahren einer Klasse; '' ohne.</summary>
function ParentOf(AType: TRttiType): string;
begin
  Result := '';
  if (AType is TRttiInstanceType) and (AType.BaseType <> nil) then
  begin
    Result := AType.BaseType.QualifiedName;
  end;
end;

/// <summary>Öffentliche Typen von APackage an ATypes anhängen.</summary>
procedure AddPackageTypes(APackage: TRttiPackage; ATypes: TList<TAtlasIdeType>);
var
  mRttiType: TRttiType;
  mType: TAtlasIdeType;
begin
  for mRttiType in APackage.GetTypes do
  begin
    if mRttiType.IsPublicType and TAtlasIdeType.FromQualified(mRttiType.QualifiedName, ParentOf(mRttiType), mType) then
    begin
      ATypes.Add(mType);
    end;
  end;
end;

class function TAtlasIdeTypeCollector.AddPackages(const ASkipped: TArray<string>;
  ATypes: TList<TAtlasIdeType>): Integer;
var
  mContext: TRttiContext;
  mPackage: TRttiPackage;
begin
  Result := 0;
  mContext := TRttiContext.Create;
  try
    for mPackage in mContext.GetPackages do
    begin
      if TAtlasIdeTypes.InFolders(mPackage.Name, ASkipped) then
      begin
        Continue;
      end;
      // Ein Package mit beschädigter RTTI darf die übrigen nicht verhindern.
      try
        AddPackageTypes(mPackage, ATypes);
      except
        on Exception do
        begin
          Inc(Result);
        end;
      end;
    end;
  finally
    mContext.Free;
  end;
end;

/// <summary>Komponente AName der Palette als Typ; False, wenn ihre Klasse nicht angemeldet ist oder in einem
/// Package unter ASkipped liegt.</summary>
function PaletteType(const AName: string; const ASkipped: TArray<string>; out AType: TAtlasIdeType): Boolean;
var
  mClass: TPersistentClass;
  mParent: string;
begin
  mClass := GetClass(AName);
  Result := (mClass <> nil) and not TAtlasIdeTypes.InFolders(GetModuleName(FindClassHInstance(mClass)), ASkipped);
  if not Result then
  begin
    Exit;
  end;
  mParent := '';
  if mClass.ClassParent <> nil then
  begin
    mParent := mClass.ClassParent.UnitName + '.' + mClass.ClassParent.ClassName;
  end;
  Result := TAtlasIdeType.FromQualified(mClass.UnitName + '.' + mClass.ClassName, mParent, AType);
end;

class procedure TAtlasIdeTypeCollector.AddPalette(const ASkipped: TArray<string>;
  ATypes: TList<TAtlasIdeType>);
var
  mServices: IOTAPackageServices;
  mPackage, mComponent: Integer;
  mType: TAtlasIdeType;
begin
  if not Supports(BorlandIDEServices, IOTAPackageServices, mServices) then
  begin
    Exit;
  end;
  for mPackage := 0 to mServices.PackageCount - 1 do
  begin
    for mComponent := 0 to mServices.ComponentCount[mPackage] - 1 do
    begin
      if PaletteType(mServices.ComponentNames[mPackage, mComponent], ASkipped, mType) then
      begin
        ATypes.Add(mType);
      end;
    end;
  end;
end;

class function TAtlasIdeTypeCollector.Collect(out AFailed: Integer): TArray<TAtlasIdeType>;
var
  mSkipped: TArray<string>;
  mTypes: TList<TAtlasIdeType>;
begin
  mSkipped := SkippedFolders;
  mTypes := TList<TAtlasIdeType>.Create;
  try
    AddPalette(mSkipped, mTypes);
    AFailed := AddPackages(mSkipped, mTypes);
    Result := mTypes.ToArray;
  finally
    mTypes.Free;
  end;
end;

end.
