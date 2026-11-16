unit Atlas.Tests.DesignSurfaceFake;

// Fälschung des Formular-Designers (IAtlasDesignSurface) für Tests der
// Designer-Werkzeuge: echte Komponenten auf einem Formular, das nie
// angezeigt wird. Die Fälschung verhält sich wie der Designer der IDE:
// Löschen nimmt die Komponente weg (geerbte nicht), Anlegen vergibt Namen
// wie „Widget1“ und hängt die Komponente in ihr Elternelement, Handler gibt
// es nur, wenn sie im „Code“ stehen (AddMethod). Die Hilfen Insert, Delete,
// Change, Select, Open und Close ändern das Formular wie ein Benutzer und
// melden das danach allen angemeldeten Empfängern, wie IDesignNotification.
// Ohne VCL: Als Formular taugt jede Wurzel, die ihre Komponenten streamt
// (TDataModule unter FPC, TForm unter Delphi).

interface

uses
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Generics.Collections,
  Atlas.Core.Designer.Surface;

type
  TAtlasDesignSurfaceFake = class(TInterfacedObject, IAtlasDesignSurface)
  private
    FRoot: TComponent;
    FListeners: TList<TAtlasDesignSurfaceListener>;
    /// <summary>Handler im „Code“; der Index + 1 ist die Codeadresse der Methode.</summary>
    FMethods: TList<string>;
    FModifiedCount: Integer;
    FDeleteRefused: TList<string>;
    /// <summary>Aus dem Code entfernte Handler (bleiben an Ereignissen zugeordnet).</summary>
    FRemoved: TList<string>;
    function UniqueName(AClass: TComponentClass): string;
    procedure Place(AComponent, AParent: TComponent);
    procedure NotifyChanged;
  public
    /// <summary>ARoot gehört danach der Fälschung (freigegeben bei Close bzw. am Ende).</summary>
    constructor Create(ARoot: TComponent);
    destructor Destroy; override;
    /// <summary>AListener bekommt die Benachrichtigungen; Abmelden mit Unlisten.</summary>
    procedure Listen(AListener: TAtlasDesignSurfaceListener);
    procedure Unlisten(AListener: TAtlasDesignSurfaceListener);
    /// <summary>Die Methode AName steht im Code des Formulars.</summary>
    procedure AddMethod(const AName: string);
    /// <summary>Die Methode AName steht nicht mehr im Code; zugeordnete Ereignisse behalten den Namen.</summary>
    procedure RemoveMethod(const AName: string);
    /// <summary>Die Komponente AKey lässt sich nicht löschen (wie geerbt).</summary>
    procedure RefuseDelete(const AKey: string);
    /// <summary>Handler AName als Wert für eine Ereignis-Eigenschaft.</summary>
    function Handler(const AName: string): TMethod;
    /// <summary>Benutzer fügt eine Komponente ein; danach Benachrichtigung.</summary>
    function Insert(AClass: TComponentClass; AParent: TComponent; const AName: string): TComponent;
    /// <summary>Benutzer löscht AComponent; danach Benachrichtigung.</summary>
    procedure Delete(AComponent: TComponent);
    /// <summary>Benutzer oder ein Werkzeug ändert Werte (AChange); danach Benachrichtigung.</summary>
    procedure Change(const AChange: TProc);
    /// <summary>Auswahl ändert sich (ohne eigene Auswahlliste).</summary>
    procedure Select;
    procedure Open;
    /// <summary>Designer schließt: Benachrichtigung, danach ist das Formular weg (Root = nil).</summary>
    procedure Close;
    { IAtlasDesignSurface }
    function Root: TComponent;
    procedure Modified;
    function DeleteComponent(const AKey: string): Boolean;
    function CreateComponent(AClass: TComponentClass; AParent: TComponent): TComponent;
    function MethodExists(const AName: string): Boolean;
    function CreateMethod(const AName: string; ATypeData: PTypeData): TMethod;
    function MethodName(const AMethod: TMethod): string;
    /// <summary>Wie oft Modified gerufen wurde.</summary>
    property ModifiedCount: Integer read FModifiedCount;
  end;

implementation

type
  /// <summary>Zugriff auf das geschützte SetParentComponent (E2362).</summary>
  TComponentAccess = class(TComponent);

{ TAtlasDesignSurfaceFake }

constructor TAtlasDesignSurfaceFake.Create(ARoot: TComponent);
begin
  inherited Create;
  FRoot := ARoot;
  FListeners := TList<TAtlasDesignSurfaceListener>.Create;
  FMethods := TList<string>.Create;
  FDeleteRefused := TList<string>.Create;
  FRemoved := TList<string>.Create;
end;

destructor TAtlasDesignSurfaceFake.Destroy;
begin
  FRoot.Free;
  FRemoved.Free;
  FDeleteRefused.Free;
  FMethods.Free;
  FListeners.Free;
  inherited Destroy;
end;

procedure TAtlasDesignSurfaceFake.Listen(AListener: TAtlasDesignSurfaceListener);
begin
  FListeners.Add(AListener);
end;

procedure TAtlasDesignSurfaceFake.Unlisten(AListener: TAtlasDesignSurfaceListener);
begin
  FListeners.Remove(AListener);
end;

procedure TAtlasDesignSurfaceFake.AddMethod(const AName: string);
begin
  FRemoved.Remove(AName);
  if FMethods.IndexOf(AName) < 0 then
  begin
    FMethods.Add(AName);
  end;
end;

procedure TAtlasDesignSurfaceFake.RemoveMethod(const AName: string);
begin
  FRemoved.Add(AName);
end;

procedure TAtlasDesignSurfaceFake.RefuseDelete(const AKey: string);
begin
  FDeleteRefused.Add(AKey);
end;

function TAtlasDesignSurfaceFake.Handler(const AName: string): TMethod;
begin
  AddMethod(AName);
  Result := CreateMethod(AName, nil);
end;

procedure TAtlasDesignSurfaceFake.NotifyChanged;
var
  mListener: TAtlasDesignSurfaceListener;
begin
  for mListener in FListeners.ToArray do
  begin
    mListener.ItemsChanged(Self);
  end;
end;

function TAtlasDesignSurfaceFake.Insert(AClass: TComponentClass; AParent: TComponent;
  const AName: string): TComponent;
begin
  Result := CreateComponent(AClass, AParent);
  if AName <> '' then
  begin
    Result.Name := AName;
  end;
  NotifyChanged;
end;

procedure TAtlasDesignSurfaceFake.Delete(AComponent: TComponent);
begin
  AComponent.Free;
  NotifyChanged;
end;

procedure TAtlasDesignSurfaceFake.Change(const AChange: TProc);
begin
  AChange();
  NotifyChanged;
end;

procedure TAtlasDesignSurfaceFake.Select;
var
  mListener: TAtlasDesignSurfaceListener;
begin
  for mListener in FListeners.ToArray do
  begin
    mListener.SelectionChanged(Self);
  end;
end;

procedure TAtlasDesignSurfaceFake.Open;
var
  mListener: TAtlasDesignSurfaceListener;
begin
  for mListener in FListeners.ToArray do
  begin
    mListener.Opened(Self);
  end;
end;

procedure TAtlasDesignSurfaceFake.Close;
var
  mListener: TAtlasDesignSurfaceListener;
begin
  for mListener in FListeners.ToArray do
  begin
    mListener.Closed(Self);
  end;
  FreeAndNil(FRoot);
end;

function TAtlasDesignSurfaceFake.Root: TComponent;
begin
  Result := FRoot;
end;

procedure TAtlasDesignSurfaceFake.Modified;
begin
  Inc(FModifiedCount);
end;

function TAtlasDesignSurfaceFake.DeleteComponent(const AKey: string): Boolean;
var
  mComponent: TComponent;
begin
  mComponent := nil;
  if (AKey <> '') and not FDeleteRefused.Contains(AKey) then
  begin
    mComponent := TAtlasDesignSurfaces.Find(FRoot, AKey);
  end;
  Result := (mComponent <> nil) and (mComponent.Owner = FRoot);
  if Result then
  begin
    mComponent.Free;
    NotifyChanged;
  end;
end;

function TAtlasDesignSurfaceFake.UniqueName(AClass: TComponentClass): string;
var
  mBase: string;
  mNumber: Integer;
begin
  mBase := AClass.ClassName.Substring(1);
  mNumber := 1;
  while FRoot.FindComponent(mBase + IntToStr(mNumber)) <> nil do
  begin
    Inc(mNumber);
  end;
  Result := mBase + IntToStr(mNumber);
end;

procedure TAtlasDesignSurfaceFake.Place(AComponent, AParent: TComponent);
begin
  if (AParent <> nil) and (AParent <> FRoot) then
  begin
    TComponentAccess(AComponent).SetParentComponent(AParent);
  end
  else if AComponent.HasParent then
  begin
    TComponentAccess(AComponent).SetParentComponent(FRoot);
  end;
end;

function TAtlasDesignSurfaceFake.CreateComponent(AClass: TComponentClass; AParent: TComponent): TComponent;
begin
  Result := AClass.Create(FRoot);
  try
    Result.Name := UniqueName(AClass);
    Place(Result, AParent);
  except
    Result.Free;
    raise;
  end;
  NotifyChanged;
end;

function TAtlasDesignSurfaceFake.MethodExists(const AName: string): Boolean;
begin
  Result := (FMethods.IndexOf(AName) >= 0) and not FRemoved.Contains(AName);
end;

function TAtlasDesignSurfaceFake.CreateMethod(const AName: string; ATypeData: PTypeData): TMethod;
begin
  AddMethod(AName);
  // Nie aufgerufen: Die Adresse kennzeichnet nur den Handler.
  Result.Code := Pointer(NativeUInt(FMethods.IndexOf(AName) + 1));
  Result.Data := FRoot;
end;

function TAtlasDesignSurfaceFake.MethodName(const AMethod: TMethod): string;
var
  mIndex: NativeInt;
begin
  Result := '';
  mIndex := NativeInt(NativeUInt(AMethod.Code)) - 1;
  if (AMethod.Data = FRoot) and (mIndex >= 0) and (mIndex < FMethods.Count) then
  begin
    Result := FMethods[mIndex];
  end;
end;

end.
