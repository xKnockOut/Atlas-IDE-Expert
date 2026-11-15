unit Atlas.Core.Outline.CrumbPlan;

// Entscheidungen der Brotkrumenleiste (#590) ohne VCL und Open Tools API:
// welche zusätzlichen Glieder die Einstellungen verlangen, wovon der gezeigte
// Pfad abhängt (neu bilden, wenn sich Stand oder Einstellungen ändern) und
// wohin ein Sprung auf ein Glied führt. Leisten, Takt, Menüs und Karte
// bleiben in Atlas.IDE.Outline.Breadcrumbs.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs;

type
  /// <summary>Wovon der gezeigte Pfad abhängt, außer dem Stand des Gliederungs-Caches: Datei, Stand der Gliederung
  /// und Einstellungen der Leiste.</summary>
  TAtlasCrumbKey = record
    FileName: string;
    Stamp: Cardinal;
    WithInterfaces: Boolean;
    ShowUnit: Boolean;
    Parts: TAtlasCrumbParts;
    /// <summary>Schlüssel zur Datei AFileName im Stand AStamp nach den Einstellungen ASettings.</summary>
    class function Create(const AFileName: string; AStamp: Cardinal;
      const ASettings: TAtlasPluginSettings): TAtlasCrumbKey; static;
    /// <summary>True, wenn AOther denselben Pfad ergibt (Dateiname ohne Groß-/Kleinschreibung).</summary>
    function Same(const AOther: TAtlasCrumbKey): Boolean;
  end;

  /// <summary>Wohin ein Sprung auf ein Glied führt: nirgends; Anfang der Datei (Unit-Glied); Stelle Line,
  /// Character (0-basiert) eines Abschnitts oder Elements.</summary>
  TAtlasCrumbJumpKind = (None, FileStart, Place);

  TAtlasCrumbJump = record
    Kind: TAtlasCrumbJumpKind;
    Line: Integer;
    Character: Integer;
  end;

  TAtlasCrumbPlan = record
  public
    /// <summary>Zusätzliche Glieder nach den Einstellungen (#1759, #1767, #1765, #1766, #1763, #1764, #1769, #1784).
    /// </summary>
    class function Parts(const ASettings: TAtlasPluginSettings): TAtlasCrumbParts; static;
    /// <summary>Sprung auf das Glied ACrumb der Gliederung ANodes: Unit-Glied an den Anfang, Abschnittsglied zu
    /// seinem gewählten Schlüsselwort, sonst zur Implementierung bzw. (ADeclaration) zur Deklaration.</summary>
    class function Jump(const ANodes: TAtlasOutlineNodes; const ACrumb: TAtlasCrumb;
      ADeclaration: Boolean): TAtlasCrumbJump; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Palette;

{ TAtlasCrumbKey }

class function TAtlasCrumbKey.Create(const AFileName: string; AStamp: Cardinal;
  const ASettings: TAtlasPluginSettings): TAtlasCrumbKey;
begin
  Result := Default(TAtlasCrumbKey);
  Result.FileName := AFileName;
  Result.Stamp := AStamp;
  Result.WithInterfaces := ASettings.BreadcrumbsInterfaces;
  Result.ShowUnit := ASettings.BreadcrumbsShowUnit;
  Result.Parts := TAtlasCrumbPlan.Parts(ASettings);
end;

function TAtlasCrumbKey.Same(const AOther: TAtlasCrumbKey): Boolean;
begin
  Result := SameText(FileName, AOther.FileName) and (Stamp = AOther.Stamp) and
    (WithInterfaces = AOther.WithInterfaces) and (ShowUnit = AOther.ShowUnit) and (Parts = AOther.Parts);
end;

{ TAtlasCrumbPlan }

class function TAtlasCrumbPlan.Parts(const ASettings: TAtlasPluginSettings): TAtlasCrumbParts;
begin
  Result := [];
  if ASettings.BreadcrumbsVisibility then
  begin
    Include(Result, TAtlasCrumbPart.Visibility);
  end;
  if ASettings.BreadcrumbsMemberBlocks then
  begin
    Include(Result, TAtlasCrumbPart.MemberBlocks);
  end;
  if ASettings.BreadcrumbsVisibilityMark then
  begin
    Include(Result, TAtlasCrumbPart.VisibilityMark);
  end;
  if ASettings.BreadcrumbsDeclarationBlocks then
  begin
    Include(Result, TAtlasCrumbPart.DeclarationBlocks);
  end;
  if ASettings.BreadcrumbsConditionals then
  begin
    Include(Result, TAtlasCrumbPart.Conditionals);
  end;
  if ASettings.BreadcrumbsRegions then
  begin
    Include(Result, TAtlasCrumbPart.Regions);
  end;
  if ASettings.BreadcrumbsStatements then
  begin
    Include(Result, TAtlasCrumbPart.Statements);
  end;
  if ASettings.BreadcrumbsOverloads then
  begin
    Include(Result, TAtlasCrumbPart.Overloads);
  end;
end;

class function TAtlasCrumbPlan.Jump(const ANodes: TAtlasOutlineNodes; const ACrumb: TAtlasCrumb;
  ADeclaration: Boolean): TAtlasCrumbJump;
var
  mTarget: Integer;
begin
  Result := Default(TAtlasCrumbJump);
  if ACrumb.Node < 0 then
  begin
    if ACrumb.Badge.Kind = TAtlasBadgeKind.Unit_ then
    begin
      Result.Kind := TAtlasCrumbJumpKind.FileStart;
    end
    else if (ACrumb.Current >= 0) and (ACrumb.Current <= High(ACrumb.Places)) then
    begin
      Result.Kind := TAtlasCrumbJumpKind.Place;
      Result.Line := ACrumb.Places[ACrumb.Current].Line;
      Result.Character := ACrumb.Places[ACrumb.Current].Character;
    end;
    Exit;
  end;
  mTarget := TAtlasBreadcrumbs.Target(ANodes, ACrumb.Node, not ADeclaration);
  if (mTarget >= 0) and (mTarget <= High(ANodes)) then
  begin
    Result.Kind := TAtlasCrumbJumpKind.Place;
    Result.Line := ANodes[mTarget].NameLine;
    Result.Character := ANodes[mTarget].NameCharacter;
  end;
end;

end.
