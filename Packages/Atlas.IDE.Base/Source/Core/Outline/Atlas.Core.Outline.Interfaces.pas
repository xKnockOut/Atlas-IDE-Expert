unit Atlas.Core.Outline.Interfaces;

// Interface-Marke an Methodengliedern der Brotkrumenleiste (#1785), Kern ohne
// VCL und OTA:
// - FromJson liest die Antwort von atlas.server.interfaceMethods: je
//   Deklarationszeile einer Methode die erfüllten Interface-Methoden mit
//   Unit, Datei und Stelle.
// - TargetsOf findet sie für einen Knoten der Gliederung über die Zeile
//   seines Namens (bei Methoden ist das Glied immer die Deklaration) und den
//   Namen ohne Besitzer.
// - MarkText ist die Marke hinter dem Namen: „[IKunde]“, bei mehreren
//   „[IKunde +1]“.

interface

uses
  System.JSON,
  Atlas.Core.Outline.Model;

type
  /// <summary>Interface-Methode, die eine Methode erfüllt.</summary>
  TAtlasInterfaceTarget = record
    /// <summary>Interface und Methode, z. B. "IKunde.Speichern".</summary>
    Name: string;
    UnitName: string;
    FileName: string;
    /// <summary>Stelle des Namens, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Interface ohne Methode ("IKunde").</summary>
    function InterfaceName: string;
  end;

  TAtlasInterfaceTargets = TArray<TAtlasInterfaceTarget>;

  /// <summary>Methode der Datei mit den Interface-Methoden, die sie erfüllt.</summary>
  TAtlasInterfaceMethod = record
    /// <summary>Zeile der Deklaration, 0-basiert.</summary>
    Line: Integer;
    /// <summary>Klasse und Methode ("TKunde.Speichern").</summary>
    Name: string;
    Targets: TAtlasInterfaceTargets;
  end;

  TAtlasInterfaceMethods = TArray<TAtlasInterfaceMethod>;

  TAtlasOutlineInterfaces = class
  public
    /// <summary>Antwort von atlas.server.interfaceMethods; leer bei anderem Inhalt.</summary>
    class function FromJson(AValue: TJSONValue): TAtlasInterfaceMethods; static;
    /// <summary>Erfüllte Interface-Methoden des Knotens ANode (Methode mit Deklaration in Zeile NameLine);
    /// leer sonst.</summary>
    class function TargetsOf(const AMethods: TAtlasInterfaceMethods; const ANodes: TAtlasOutlineNodes;
      ANode: Integer): TAtlasInterfaceTargets; static;
    /// <summary>Marke hinter dem Namen: „[IKunde]“, „[IKunde +1]“; leer ohne Ziele.</summary>
    class function MarkText(const ATargets: TAtlasInterfaceTargets): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Uris;

{ TAtlasInterfaceTarget }

function TAtlasInterfaceTarget.InterfaceName: string;
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', Name);
  Result := Name;
  if mDot > 0 then
  begin
    Result := Copy(Name, 1, mDot - 1);
  end;
end;

{ TAtlasOutlineInterfaces }

function ReadTarget(AValue: TJSONValue; out ATarget: TAtlasInterfaceTarget): Boolean;
var
  mItem: TJSONObject;
begin
  ATarget := Default(TAtlasInterfaceTarget);
  Result := AValue is TJSONObject;
  if not Result then
  begin
    Exit;
  end;
  mItem := TJSONObject(AValue);
  ATarget.Name := mItem.GetValue<string>('name', '');
  ATarget.UnitName := mItem.GetValue<string>('unit', '');
  ATarget.FileName := StringReplace(TTextUris.ToPath(mItem.GetValue<string>('uri', '')), '/', '\', [rfReplaceAll]);
  ATarget.Line := mItem.GetValue<Integer>('line', -1);
  ATarget.Character := mItem.GetValue<Integer>('character', 0);
  Result := (ATarget.Name <> '') and (ATarget.Line >= 0);
end;

class function TAtlasOutlineInterfaces.FromJson(AValue: TJSONValue): TAtlasInterfaceMethods;
var
  mMethods, mTargets: TJSONValue;
  mItem, mTargetItem: TJSONValue;
  mMethod: TAtlasInterfaceMethod;
  mTarget: TAtlasInterfaceTarget;
begin
  Result := nil;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mMethods := TJSONObject(AValue).GetValue('methods');
  if not (mMethods is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mMethods) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mMethod := Default(TAtlasInterfaceMethod);
    mMethod.Line := TJSONObject(mItem).GetValue<Integer>('line', -1);
    mMethod.Name := TJSONObject(mItem).GetValue<string>('name', '');
    mTargets := TJSONObject(mItem).GetValue('interfaces');
    if mTargets is TJSONArray then
    begin
      for mTargetItem in TJSONArray(mTargets) do
      begin
        if ReadTarget(mTargetItem, mTarget) then
        begin
          mMethod.Targets := mMethod.Targets + [mTarget];
        end;
      end;
    end;
    if (mMethod.Line >= 0) and (Length(mMethod.Targets) > 0) then
    begin
      Result := Result + [mMethod];
    end;
  end;
end;

/// <summary>Name ohne Besitzer: "TKunde.Speichern" → "Speichern".</summary>
function BareName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

class function TAtlasOutlineInterfaces.TargetsOf(const AMethods: TAtlasInterfaceMethods;
  const ANodes: TAtlasOutlineNodes; ANode: Integer): TAtlasInterfaceTargets;
var
  mMethod: TAtlasInterfaceMethod;
  mNode: TAtlasOutlineNode;
begin
  Result := nil;
  if (ANode < 0) or (ANode > High(ANodes)) then
  begin
    Exit;
  end;
  mNode := ANodes[ANode];
  if mNode.Category <> TAtlasOutlineCategory.Method then
  begin
    Exit;
  end;
  for mMethod in AMethods do
  begin
    if (mMethod.Line = mNode.NameLine) and SameText(BareName(mMethod.Name), BareName(mNode.Name)) then
    begin
      Exit(mMethod.Targets);
    end;
  end;
end;

class function TAtlasOutlineInterfaces.MarkText(const ATargets: TAtlasInterfaceTargets): string;
begin
  Result := '';
  if Length(ATargets) = 0 then
  begin
    Exit;
  end;
  Result := ATargets[0].InterfaceName;
  if Length(ATargets) > 1 then
  begin
    Result := Result + ' +' + IntToStr(Length(ATargets) - 1);
  end;
  Result := '[' + Result + ']';
end;

end.
