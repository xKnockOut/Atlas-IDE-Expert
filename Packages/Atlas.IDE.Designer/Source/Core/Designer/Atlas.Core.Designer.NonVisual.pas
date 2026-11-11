unit Atlas.Core.Designer.NonVisual;

// Leiste für nichtvisuelle Komponenten (#609), ohne VCL und Windows.
// - Gruppe nach Art: Daten (TDataSet-Nachfahren, TDataSource, Verbindungen),
//   Aktionen und Menüs, Dialoge, Bilder (Bildlisten, Bildsammlungen),
//   Sonstiges. Gesucht wird die Klasse, dann ihre Vorfahren; bekannte Klassen
//   (TFDQuery, TOpenDialog …) stehen auch ohne Vorfahren in der Tabelle.
// - Zeilen: nach Gruppe, dann nach Namen; Filter auf den Namen ohne
//   Groß-/Kleinschreibung.
// - Freie Stelle: am unteren Rand des Formulars von links, dann Reihe für
//   Reihe darüber; belegt ist eine Stelle, deren Symbol ein vorhandenes
//   überdeckt. Alles in Pixeln der DFM (Left/Top der nichtvisuellen
//   Komponente).

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasTrayGroup = (Data, Actions, Dialogs, Images, Other);
{$SCOPEDENUMS OFF}

  TAtlasTrayItem = record
    Name: string;
    /// <summary>Klasse und Vorfahren, die Klasse zuerst.</summary>
    ClassChain: TArray<string>;
    Group: TAtlasTrayGroup;
    /// <summary>Lage des Symbols (Left/Top der DFM).</summary>
    Position: TPoint;
    function ClassName: string;
  end;

  TAtlasNonVisualTray = class
  public const
    /// <summary>Kantenlänge eines Symbols im Designer in Pixeln der DFM.</summary>
    cIconSize = 28;
    cGap = 8;
  public
    /// <summary>Gruppe nach Klasse und Vorfahren.</summary>
    class function GroupOf(const AClassChain: TArray<string>): TAtlasTrayGroup; static;
    /// <summary>Gruppen gesetzt, nach Gruppe und Namen sortiert, nur Namen mit AFilter.</summary>
    class function Rows(const AItems: TArray<TAtlasTrayItem>; const AFilter: string): TArray<TAtlasTrayItem>; static;
    /// <summary>Freie Stelle für ein neues Symbol im Client AClient neben den Symbolen AOccupied.</summary>
    class function FreePosition(const AOccupied: TArray<TPoint>; const AClient: TSize): TPoint; static;
    /// <summary>Kurzer Schlüssel der Gruppe (data, actions, dialogs, images, other).</summary>
    class function GroupKey(AGroup: TAtlasTrayGroup): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Defaults,
  System.Generics.Collections;

type
  TGroupClass = record
    ClassName: string;
    Group: TAtlasTrayGroup;
  end;

const
  cMargin = 8;
  cGroupKeys: array[TAtlasTrayGroup] of string = ('data', 'actions', 'dialogs', 'images', 'other');
  cGroupClasses: array[0..33] of TGroupClass = (
    // Vorfahren
    (ClassName: 'TDataSet'; Group: TAtlasTrayGroup.Data), (ClassName: 'TDataSource'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TCustomConnection'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TFDCustomManager'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TFDCustomTransaction'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TBasicAction'; Group: TAtlasTrayGroup.Actions),
    (ClassName: 'TCustomActionList'; Group: TAtlasTrayGroup.Actions),
    (ClassName: 'TCustomActionManager'; Group: TAtlasTrayGroup.Actions),
    (ClassName: 'TMenu'; Group: TAtlasTrayGroup.Actions), (ClassName: 'TMenuItem'; Group: TAtlasTrayGroup.Actions),
    (ClassName: 'TCommonDialog'; Group: TAtlasTrayGroup.Dialogs),
    (ClassName: 'TCustomImageList'; Group: TAtlasTrayGroup.Images),
    (ClassName: 'TCustomImageCollection'; Group: TAtlasTrayGroup.Images),
    // Bekannte Klassen, falls die Vorfahren fehlen (Text der DFM)
    (ClassName: 'TFDQuery'; Group: TAtlasTrayGroup.Data), (ClassName: 'TFDTable'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TFDMemTable'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TFDStoredProc'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TFDConnection'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TFDTransaction'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TClientDataSet'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TADOQuery'; Group: TAtlasTrayGroup.Data), (ClassName: 'TADOConnection'; Group: TAtlasTrayGroup.Data),
    (ClassName: 'TActionList'; Group: TAtlasTrayGroup.Actions),
    (ClassName: 'TActionManager'; Group: TAtlasTrayGroup.Actions),
    (ClassName: 'TMainMenu'; Group: TAtlasTrayGroup.Actions), (ClassName: 'TPopupMenu'; Group: TAtlasTrayGroup.Actions),
    (ClassName: 'TOpenDialog'; Group: TAtlasTrayGroup.Dialogs),
    (ClassName: 'TSaveDialog'; Group: TAtlasTrayGroup.Dialogs),
    (ClassName: 'TFontDialog'; Group: TAtlasTrayGroup.Dialogs),
    (ClassName: 'TColorDialog'; Group: TAtlasTrayGroup.Dialogs),
    (ClassName: 'TFileOpenDialog'; Group: TAtlasTrayGroup.Dialogs),
    (ClassName: 'TImageList'; Group: TAtlasTrayGroup.Images),
    (ClassName: 'TVirtualImageList'; Group: TAtlasTrayGroup.Images),
    (ClassName: 'TImageCollection'; Group: TAtlasTrayGroup.Images));

{ TAtlasTrayItem }

function TAtlasTrayItem.ClassName: string;
begin
  Result := '';
  if Length(ClassChain) > 0 then
  begin
    Result := ClassChain[0];
  end;
end;

{ TAtlasNonVisualTray }

class function TAtlasNonVisualTray.GroupKey(AGroup: TAtlasTrayGroup): string;
begin
  Result := cGroupKeys[AGroup];
end;

class function TAtlasNonVisualTray.GroupOf(const AClassChain: TArray<string>): TAtlasTrayGroup;
var
  mClass: string;
  mEntry: TGroupClass;
begin
  // Die Klasse vor ihren Vorfahren: TActionManager steht vor TComponent.
  for mClass in AClassChain do
  begin
    for mEntry in cGroupClasses do
    begin
      if SameText(mEntry.ClassName, mClass) then
      begin
        Exit(mEntry.Group);
      end;
    end;
  end;
  Result := TAtlasTrayGroup.Other;
end;

class function TAtlasNonVisualTray.Rows(const AItems: TArray<TAtlasTrayItem>;
  const AFilter: string): TArray<TAtlasTrayItem>;
var
  mItem: TAtlasTrayItem;
  mFilter: string;
begin
  Result := nil;
  mFilter := AFilter.Trim.ToLower;
  for mItem in AItems do
  begin
    if (mFilter = '') or mItem.Name.ToLower.Contains(mFilter) then
    begin
      Result := Result + [mItem];
      Result[High(Result)].Group := GroupOf(mItem.ClassChain);
    end;
  end;
  TArray.Sort<TAtlasTrayItem>(Result, TComparer<TAtlasTrayItem>.Construct(
    function(const ALeft, ARight: TAtlasTrayItem): Integer
    begin
      Result := Ord(ALeft.Group) - Ord(ARight.Group);
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Name, ARight.Name);
      end;
    end));
end;

function Occupied(const AOccupied: TArray<TPoint>; const APoint: TPoint): Boolean;
var
  mPoint: TPoint;
begin
  for mPoint in AOccupied do
  begin
    if (Abs(mPoint.X - APoint.X) < TAtlasNonVisualTray.cIconSize) and
      (Abs(mPoint.Y - APoint.Y) < TAtlasNonVisualTray.cIconSize) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasNonVisualTray.FreePosition(const AOccupied: TArray<TPoint>; const AClient: TSize): TPoint;
var
  mX, mY, mStep: Integer;
begin
  mStep := cIconSize + cGap;
  mY := AClient.cy - cIconSize - cMargin;
  while mY >= cMargin do
  begin
    mX := cMargin;
    while mX + cIconSize <= AClient.cx - cMargin do
    begin
      Result := TPoint.Create(mX, mY);
      if not Occupied(AOccupied, Result) then
      begin
        Exit;
      end;
      Inc(mX, mStep);
    end;
    Dec(mY, mStep);
  end;
  // Kein Platz (sehr kleines oder volles Formular): links oben.
  Result := TPoint.Create(cMargin, cMargin);
end;

end.
