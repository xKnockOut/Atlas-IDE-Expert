unit Atlas.Core.Lsp.IdeTypes;

// Typen aus den geladenen Packages der IDE für den Server (atlas/ideTypes). Die IDE kennt jeden Typ eines
// geladenen Packages samt Unit über die RTTI, auch wenn das Package nur als BPL/DCP/DCU installiert ist und die
// .pas fehlt. Der Server nutzt sie, damit unresolved-type und unresolved-identifier für solche Typen schweigen,
// die Schnellkorrektur die Unit vorschlägt und die Vervollständigung sie anbietet. Hier ohne Open Tools API und
// RTTI: Aufteilen qualifizierter Namen und das JSON der Meldung; gesammelt wird in Atlas.IDE.CodeInsight.IdeTypes.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  /// <summary>Ein Typ der IDE mit Unit und, bei Klassen, dem direkten Vorfahren samt Unit.</summary>
  TAtlasIdeType = record
    Name: string;
    UnitName: string;
    /// <summary>Vorfahr mit Unit (Vcl.Controls.TCustomControl); '' ohne.</summary>
    Parent: string;
    /// <summary>Typ aus dem qualifizierten Namen AQualified (Unit.Typ) und dem qualifizierten Vorfahren
    /// AParent; False für Namen ohne Unit und generische Instanzen (mit &lt;).</summary>
    class function FromQualified(const AQualified, AParent: string; out AType: TAtlasIdeType): Boolean; static;
  end;

  TAtlasIdeTypes = class
  public const
    Method = 'atlas/ideTypes';
  public
    /// <summary>Parameter von atlas/ideTypes: je Unit ein Eintrag in der Reihenfolge des ersten Vorkommens, ohne
    /// doppelte Typen. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const ATypes: TArray<TAtlasIdeType>): TJSONObject; static;
    /// <summary>Liegt AFileName unter einem der Ordner AFolders (ohne Groß-/Kleinschreibung)?</summary>
    class function InFolders(const AFileName: string; const AFolders: TArray<string>): Boolean; static;
  end;

implementation

{ TAtlasIdeType }

class function TAtlasIdeType.FromQualified(const AQualified, AParent: string; out AType: TAtlasIdeType): Boolean;
var
  mDot: Integer;
begin
  AType := Default(TAtlasIdeType);
  mDot := AQualified.LastIndexOf('.');
  Result := (mDot > 0) and (mDot < AQualified.Length - 1) and (Pos('<', AQualified) = 0);
  if Result then
  begin
    AType.UnitName := AQualified.Substring(0, mDot);
    AType.Name := AQualified.Substring(mDot + 1);
    AType.Parent := AParent;
  end;
end;

{ TAtlasIdeTypes }

/// <summary>Element von "types": Name allein oder mit Vorfahr.</summary>
function TypeJson(const AType: TAtlasIdeType): TJSONValue;
var
  mObject: TJSONObject;
begin
  if AType.Parent = '' then
  begin
    Exit(TJSONString.Create(AType.Name));
  end;
  mObject := TJSONObject.Create;
  mObject.AddPair('name', AType.Name);
  mObject.AddPair('parent', AType.Parent);
  Result := mObject;
end;

/// <summary>Liste "types" der Unit AUnit in AUnits, bei Bedarf neu angelegt (AOrder hält die Reihenfolge).
/// </summary>
function TypesOf(AUnits: TDictionary<string, TJSONArray>; AOrder: TJSONArray; const AUnit: string): TJSONArray;
var
  mEntry: TJSONObject;
begin
  if AUnits.TryGetValue(UpperCase(AUnit), Result) then
  begin
    Exit;
  end;
  Result := TJSONArray.Create;
  mEntry := TJSONObject.Create;
  mEntry.AddPair('unit', AUnit);
  mEntry.AddPair('types', Result);
  AOrder.AddElement(mEntry);
  AUnits.Add(UpperCase(AUnit), Result);
end;

class function TAtlasIdeTypes.ToJson(const ATypes: TArray<TAtlasIdeType>): TJSONObject;
var
  mOrder: TJSONArray;
  mUnits: TDictionary<string, TJSONArray>;
  mSeen: TDictionary<string, Boolean>;
  mType: TAtlasIdeType;
  mKey: string;
begin
  Result := TJSONObject.Create;
  mOrder := TJSONArray.Create;
  Result.AddPair('units', mOrder);
  mUnits := TDictionary<string, TJSONArray>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mType in ATypes do
    begin
      mKey := UpperCase(mType.UnitName + '.' + mType.Name);
      if (mType.Name <> '') and (mType.UnitName <> '') and not mSeen.ContainsKey(mKey) then
      begin
        mSeen.Add(mKey, True);
        TypesOf(mUnits, mOrder, mType.UnitName).AddElement(TypeJson(mType));
      end;
    end;
  finally
    mSeen.Free;
    mUnits.Free;
  end;
end;

class function TAtlasIdeTypes.InFolders(const AFileName: string; const AFolders: TArray<string>): Boolean;
var
  mFolder: string;
begin
  for mFolder in AFolders do
  begin
    if (mFolder <> '') and AFileName.StartsWith(IncludeTrailingPathDelimiter(mFolder), True) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
