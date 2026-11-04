unit Atlas.Common.Rules.Builtin.Packages;

// Prüfung an Package-Dateien (#46): Units, die implizit ins Package gezogen
// würden, wie die Compilerwarnung W1033. Ausgehend von den Units in contains
// folgt die Regel den uses-Listen (interface und implementation) über den
// Index. Eine Unit ist implizit, wenn sie weder in contains steht noch zu einem
// Package aus requires gehört (TRuleContext.PackageProvides) und als Quelltext
// des Projekts gefunden wird. Bibliotheks-Units, nicht auffindbare Units und
// Packages, deren Inhalt unbekannt ist, ergeben keinen Treffer. Gemeldet wird
// am contains-Eintrag, über den die Unit erreicht wird; die Korrektur nimmt sie
// in contains auf. Ohne Index oder PackageProvides (Linter) schweigt die Regel.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ImplicitPackageImportRuleId = 'implicit-package-import';

type
  TImplicitPackageImportRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterPackageRules(ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.PackageReader;

type
  TPending = record
    UnitName: string;
    /// <summary>contains-Eintrag, über den die Unit erreicht wurde.</summary>
    Origin: Integer;
  end;

  /// <summary>Ein Lauf über die uses-Listen ab contains; meldet jede implizite Unit einmal.</summary>
  TImplicitImportWalk = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FSource: TPackageSource;
    FRequired: TArray<string>;
    FSeen: TDictionary<string, Boolean>;
    FPending: TQueue<TPending>;
    procedure Enqueue(const AUnitName: string; const AOrigin: Integer);
    procedure Consider(const AItem: TPending; const AName: string);
    function IsProvided(const AName: string): Boolean;
    procedure ReportImplicit(const AItem: TPending; const AName: string; const AUsed: TUnitIndex);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport; const ASource: TPackageSource);
    destructor Destroy; override;
    procedure Run;
  end;

function FindIndexed(const AContext: TRuleContext; const AUnitName: string; out AUnit: TUnitIndex): Boolean;
begin
  Result := AContext.Index.FindUnit(AUnitName, AUnit);
  if not Result and Assigned(AContext.EnsureUnit) and AContext.EnsureUnit(AUnitName) then
  begin
    Result := AContext.Index.FindUnit(AUnitName, AUnit);
  end;
end;

/// <summary>requires des Packages und, über PackageRequires, die Packages, die diese verlangen: dcc sieht deren
/// Units ebenso (Atlas.Windows → Atlas.Common → Atlas.Text); ohne Doppelte, in Suchreihenfolge.</summary>
function RequiredClosure(const AContext: TRuleContext; const ASource: TPackageSource): TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mList: TList<string>;
  mEntry: TPackageEntry;
  mPosition: Integer;
  mRequired: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mList := TList<string>.Create;
  try
    for mEntry in ASource.Requires do
    begin
      if not mSeen.ContainsKey(UpperCase(mEntry.Name)) then
      begin
        mSeen.Add(UpperCase(mEntry.Name), True);
        mList.Add(mEntry.Name);
      end;
    end;
    mPosition := 0;
    while Assigned(AContext.PackageRequires) and (mPosition < mList.Count) do
    begin
      for mRequired in AContext.PackageRequires(mList[mPosition]) do
      begin
        if not mSeen.ContainsKey(UpperCase(mRequired)) then
        begin
          mSeen.Add(UpperCase(mRequired), True);
          mList.Add(mRequired);
        end;
      end;
      Inc(mPosition);
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mSeen.Free;
  end;
end;

{ TImplicitImportWalk }

constructor TImplicitImportWalk.Create(const AContext: TRuleContext; const AReport: IRuleReport;
  const ASource: TPackageSource);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FSource := ASource;
  FRequired := RequiredClosure(AContext, ASource);
  FSeen := TDictionary<string, Boolean>.Create;
  FPending := TQueue<TPending>.Create;
end;

destructor TImplicitImportWalk.Destroy;
begin
  FPending.Free;
  FSeen.Free;
  inherited;
end;

procedure TImplicitImportWalk.Enqueue(const AUnitName: string; const AOrigin: Integer);
var
  mItem: TPending;
begin
  mItem.UnitName := AUnitName;
  mItem.Origin := AOrigin;
  FPending.Enqueue(mItem);
end;

procedure TImplicitImportWalk.Run;
var
  mIndex: Integer;
  mItem: TPending;
  mIndexed: TUnitIndex;
  mName: string;
begin
  for mIndex := 0 to High(FSource.Contains) do
  begin
    FSeen.AddOrSetValue(UpperCase(FSource.Contains[mIndex].Name), True);
    Enqueue(FSource.Contains[mIndex].Name, mIndex);
  end;
  while FPending.Count > 0 do
  begin
    mItem := FPending.Dequeue;
    if Assigned(FContext.Cancelled) and FContext.Cancelled() then
    begin
      Exit;
    end;
    // Bibliotheks-Units gehören zu Packages der Installation; ihnen wird nicht gefolgt.
    if FindIndexed(FContext, mItem.UnitName, mIndexed) and not mIndexed.Library_ then
    begin
      for mName in mIndexed.InterfaceUses + mIndexed.ImplementationUses do
      begin
        Consider(mItem, mName);
      end;
    end;
  end;
end;

procedure TImplicitImportWalk.Consider(const AItem: TPending; const AName: string);
var
  mUsed: TUnitIndex;
begin
  if FSeen.ContainsKey(UpperCase(AName)) then
  begin
    Exit;
  end;
  FSeen.Add(UpperCase(AName), True);
  if IsProvided(AName) or not FindIndexed(FContext, AName, mUsed) or mUsed.Library_ then
  begin
    Exit;
  end;
  ReportImplicit(AItem, AName, mUsed);
  // Was die implizite Unit verwendet, kommt ebenfalls mit.
  Enqueue(AName, AItem.Origin);
end;

function TImplicitImportWalk.IsProvided(const AName: string): Boolean;
var
  mPackage: string;
begin
  Result := False;
  for mPackage in FRequired do
  begin
    if FContext.PackageProvides(mPackage, AName) <> TRulePackageAnswer.No then
    begin
      Exit(True);
    end;
  end;
end;

procedure TImplicitImportWalk.ReportImplicit(const AItem: TPending; const AName: string; const AUsed: TUnitIndex);
var
  mPath: string;
  mFix: TRuleFix;
begin
  mPath := AUsed.FileName;
  if FContext.FileName <> '' then
  begin
    mPath := ExtractRelativePath(ExtractFilePath(FContext.FileName), AUsed.FileName);
  end;
  mFix := TRuleFix.Create(Format('"%s" in contains aufnehmen', [AName]),
    [TRuleEdit.Create(TTextRange.Create(FSource.ContainsEnd, FSource.ContainsEnd),
    TPackageReader.ContainsInsertion(AName, mPath, TTextLines.LineBreakOf(FContext.Text)))]);
  FReport.Add(FSource.Contains[AItem.Origin].Range,
    Format('"%s" wird implizit ins Package gezogen: %s verwendet %s, und die Unit steht weder in ' +
    'contains noch in einem requires-Package (W1033).', [AName, AItem.UnitName, AName]), [mFix]);
end;

{ TImplicitPackageImportRule }

function TImplicitPackageImportRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ImplicitPackageImportRuleId, TRuleSeverity.Warning,
    'Unit wird implizit ins Package gezogen: weder in contains noch in einem requires-Package (wie W1033).');
end;

procedure TImplicitPackageImportRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mSource: TPackageSource;
  mWalk: TImplicitImportWalk;
begin
  if (AContext.Index = nil) or not Assigned(AContext.PackageProvides) then
  begin
    Exit;
  end;
  mSource := TPackageReader.Read(AContext.Text);
  if not mSource.IsPackage or not mSource.HasContains then
  begin
    Exit;
  end;
  mWalk := TImplicitImportWalk.Create(AContext, AReport, mSource);
  try
    mWalk.Run;
  finally
    mWalk.Free;
  end;
end;

procedure RegisterPackageRules(ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TImplicitPackageImportRule.Create);
end;

end.
