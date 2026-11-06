unit Atlas.IDE.CodeInsight.IdeMembers;

// Sammelt für atlas/ideMembers die Mitglieder der Typen in Units ohne Quelltext (Hauptthread, auf Nachfrage des
// Servers nach dem Index). Quelle ist die RTTI der geladenen Packages außerhalb der Installation: bei Klassen
// Vorfahr, Interfaces, Felder, Properties (auch Array-Properties) und Methoden mit Parametern, sichtbar ab
// protected; bei Interfaces und Records ebenso, bei Aufzählungen die Werte. Was die RTTI nicht kennt, fehlt:
// Methoden ohne erweiterte RTTI ({$RTTI EXPLICIT METHODS([])}), Vorgabewerte von Parametern, private Mitglieder.

interface

uses
  System.Rtti,
  Atlas.Core.Lsp.IdeMembers;

type
  TAtlasIdeMemberCollector = class
  private
    class function Detail(AType: TRttiType; const AUnit: string; out ADetail: TAtlasIdeTypeDetail): Boolean;
      static;
  public
    /// <summary>Typen samt Mitgliedern der Units AUnits aus den geladenen Packages außerhalb der Installation;
    /// nur im Hauptthread. AFailed: Packages, deren RTTI nicht lesbar war.</summary>
    class function Details(const AUnits: TArray<string>; out AFailed: Integer): TArray<TAtlasIdeTypeDetail>; static;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  System.Generics.Collections,
  Atlas.Core.Lsp.IdeTypes,
  Atlas.IDE.CodeInsight.IdeTypes;

/// <summary>Typ als Text mit Unit (System.Integer); '' ohne Typ oder bei namenlosen Typen.</summary>
function TypeText(AType: TRttiType): string;
begin
  Result := '';
  if AType = nil then
  begin
    Exit;
  end;
  try
    if AType.IsPublicType then
    begin
      Result := AType.QualifiedName;
    end
    else
    begin
      Result := AType.Name;
    end;
  except
    on Exception do
    begin
      Result := AType.Name;
    end;
  end;
  // Namenlose Typen (array of …, Mengen im Parameter) heißen ':…'.
  if Pos(':', Result) > 0 then
  begin
    Result := '';
  end;
end;

function VisibilityText(AVisibility: TMemberVisibility): string;
begin
  case AVisibility of
    mvProtected:
      Result := 'protected';
    mvPublic:
      Result := 'public';
    mvPublished:
      Result := 'published';
  else
    Result := '';
  end;
end;

function FlagText(AFlags: TParamFlags): string;
begin
  Result := '';
  if pfVar in AFlags then
  begin
    Result := 'var';
  end
  else if pfConst in AFlags then
  begin
    Result := 'const';
  end
  else if pfOut in AFlags then
  begin
    Result := 'out';
  end;
end;

function ParamsOf(AMethod: TRttiMethod): TArray<TAtlasIdeParam>;
var
  mParam: TRttiParameter;
begin
  Result := nil;
  for mParam in AMethod.GetParameters do
  begin
    Result := Result + [TAtlasIdeParam.Make(mParam.Name, TypeText(mParam.ParamType), FlagText(mParam.Flags))];
  end;
end;

/// <summary>Art einer Methode für die Ersatz-Unit; False für Klassenkonstruktoren und Operatoren.</summary>
function MethodKindOf(AMethod: TRttiMethod; out AKind: string; out AStatic: Boolean): Boolean;
begin
  AStatic := AMethod.MethodKind in [mkClassProcedure, mkClassFunction];
  case AMethod.MethodKind of
    mkProcedure, mkSafeProcedure, mkClassProcedure:
      AKind := 'procedure';
    mkFunction, mkSafeFunction, mkClassFunction:
      AKind := 'function';
    mkConstructor:
      AKind := 'constructor';
    mkDestructor:
      AKind := 'destructor';
  else
    AKind := '';
  end;
  Result := AKind <> '';
end;

/// <summary>Mitglied mit Art, Name und Sichtbarkeit; False, wenn es nicht sichtbar ist.</summary>
function NewMember(AMember: TRttiMember; const AKind: string; out AResult: TAtlasIdeMember): Boolean;
begin
  AResult := Default(TAtlasIdeMember);
  AResult.Kind := AKind;
  AResult.Name := AMember.Name;
  AResult.Visibility := VisibilityText(AMember.Visibility);
  Result := (AResult.Visibility <> '') and IsValidIdent(AResult.Name);
end;

procedure AddFields(AType: TRttiType; AMembers: TList<TAtlasIdeMember>);
var
  mField: TRttiField;
  mMember: TAtlasIdeMember;
begin
  for mField in AType.GetDeclaredFields do
  begin
    if NewMember(mField, 'field', mMember) then
    begin
      mMember.TypeName := TypeText(mField.FieldType);
      AMembers.Add(mMember);
    end;
  end;
end;

procedure AddProperties(AType: TRttiType; AMembers: TList<TAtlasIdeMember>);
var
  mProperty: TRttiProperty;
  mIndexed: TRttiIndexedProperty;
  mMember: TAtlasIdeMember;
begin
  for mProperty in AType.GetDeclaredProperties do
  begin
    if NewMember(mProperty, 'property', mMember) then
    begin
      mMember.TypeName := TypeText(mProperty.PropertyType);
      AMembers.Add(mMember);
    end;
  end;
  for mIndexed in AType.GetDeclaredIndexedProperties do
  begin
    if NewMember(mIndexed, 'property', mMember) then
    begin
      mMember.TypeName := TypeText(mIndexed.PropertyType);
      mMember.IsDefault := mIndexed.IsDefault;
      // Die Indexparameter sind die Parameter des Lesezugriffs.
      if mIndexed.ReadMethod <> nil then
      begin
        mMember.Index := ParamsOf(mIndexed.ReadMethod);
      end;
      AMembers.Add(mMember);
    end;
  end;
end;

procedure AddMethods(AType: TRttiType; AMembers: TList<TAtlasIdeMember>);
var
  mMethod: TRttiMethod;
  mMember: TAtlasIdeMember;
  mKind: string;
  mStatic: Boolean;
begin
  for mMethod in AType.GetDeclaredMethods do
  begin
    if MethodKindOf(mMethod, mKind, mStatic) and NewMember(mMethod, mKind, mMember) then
    begin
      mMember.IsStatic := mStatic;
      mMember.Params := ParamsOf(mMethod);
      if mMethod.ReturnType <> nil then
      begin
        mMember.TypeName := TypeText(mMethod.ReturnType);
      end;
      AMembers.Add(mMember);
    end;
  end;
end;

function MembersOf(AType: TRttiType): TArray<TAtlasIdeMember>;
var
  mMembers: TList<TAtlasIdeMember>;
begin
  mMembers := TList<TAtlasIdeMember>.Create;
  try
    AddFields(AType, mMembers);
    AddProperties(AType, mMembers);
    AddMethods(AType, mMembers);
    Result := mMembers.ToArray;
  finally
    mMembers.Free;
  end;
end;

function InterfacesOf(AType: TRttiInstanceType): TArray<string>;
var
  mInterface: TRttiInterfaceType;
  mName: string;
begin
  Result := nil;
  for mInterface in AType.GetImplementedInterfaces do
  begin
    mName := TypeText(mInterface);
    if mName <> '' then
    begin
      Result := Result + [mName];
    end;
  end;
end;

function EnumValuesOf(AType: TRttiEnumerationType): TArray<string>;
var
  mValue: Integer;
begin
  Result := nil;
  for mValue := AType.MinValue to AType.MaxValue do
  begin
    Result := Result + [GetEnumName(AType.Handle, mValue)];
  end;
end;

/// <summary>Art des Typs für die Ersatz-Unit; '' für Arten ohne Mitglieder (Mengen, Zeiger, Aliase).</summary>
function KindOf(AType: TRttiType): string;
begin
  if AType is TRttiInstanceType then
  begin
    Result := 'class';
  end
  else if AType is TRttiInterfaceType then
  begin
    Result := 'interface';
  end
  else if AType is TRttiRecordType then
  begin
    Result := 'record';
  end
  else if (AType is TRttiEnumerationType) and (AType.Handle <> TypeInfo(Boolean)) then
  begin
    Result := 'enum';
  end
  else
  begin
    Result := '';
  end;
end;

class function TAtlasIdeMemberCollector.Detail(AType: TRttiType; const AUnit: string;
  out ADetail: TAtlasIdeTypeDetail): Boolean;
begin
  ADetail := Default(TAtlasIdeTypeDetail);
  ADetail.UnitName := AUnit;
  ADetail.Name := AType.Name;
  ADetail.Kind := KindOf(AType);
  Result := (ADetail.Kind <> '') and IsValidIdent(ADetail.Name);
  if not Result then
  begin
    Exit;
  end;
  if ADetail.Kind = 'enum' then
  begin
    ADetail.Values := EnumValuesOf(TRttiEnumerationType(AType));
    Exit;
  end;
  if AType.BaseType <> nil then
  begin
    ADetail.Parent := TypeText(AType.BaseType);
  end;
  if AType is TRttiInstanceType then
  begin
    ADetail.Interfaces := InterfacesOf(TRttiInstanceType(AType));
  end;
  ADetail.Members := MembersOf(AType);
end;

/// <summary>Typen von APackage in den Units AWanted (Großbuchstaben) an ADetails anhängen.</summary>
procedure AddPackageDetails(APackage: TRttiPackage; AWanted: TDictionary<string, Boolean>;
  ADetails: TList<TAtlasIdeTypeDetail>);
var
  mRttiType: TRttiType;
  mType: TAtlasIdeType;
  mDetail: TAtlasIdeTypeDetail;
begin
  for mRttiType in APackage.GetTypes do
  begin
    if mRttiType.IsPublicType and TAtlasIdeType.FromQualified(mRttiType.QualifiedName, '', mType) and
      AWanted.ContainsKey(UpperCase(mType.UnitName)) and
      TAtlasIdeMemberCollector.Detail(mRttiType, mType.UnitName, mDetail) then
    begin
      ADetails.Add(mDetail);
    end;
  end;
end;

class function TAtlasIdeMemberCollector.Details(const AUnits: TArray<string>;
  out AFailed: Integer): TArray<TAtlasIdeTypeDetail>;
var
  mUnit: string;
  mFolders: TArray<string>;
  mWanted: TDictionary<string, Boolean>;
  mDetails: TList<TAtlasIdeTypeDetail>;
  mContext: TRttiContext;
  mPackage: TRttiPackage;
begin
  AFailed := 0;
  mFolders := TAtlasIdeTypeCollector.SkippedFolders;
  mWanted := TDictionary<string, Boolean>.Create;
  mDetails := TList<TAtlasIdeTypeDetail>.Create;
  mContext := TRttiContext.Create;
  try
    for mUnit in AUnits do
    begin
      mWanted.AddOrSetValue(UpperCase(mUnit), True);
    end;
    for mPackage in mContext.GetPackages do
    begin
      if TAtlasIdeTypes.InFolders(mPackage.Name, mFolders) then
      begin
        Continue;
      end;
      // Ein Package mit beschädigter RTTI darf die übrigen nicht verhindern.
      try
        AddPackageDetails(mPackage, mWanted, mDetails);
      except
        on Exception do
        begin
          Inc(AFailed);
        end;
      end;
    end;
    Result := mDetails.ToArray;
  finally
    mContext.Free;
    mDetails.Free;
    mWanted.Free;
  end;
end;

end.
