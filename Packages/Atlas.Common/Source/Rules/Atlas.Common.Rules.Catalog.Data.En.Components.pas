unit Atlas.Common.Rules.Catalog.Data.En.Components;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesEnComponents: array[0..79] of string = (
    '{',
    '      "id": "component-create-without-override",',
    '      "name": "Component constructor without override",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "components",',
    '      "description": "A TComponent descendant declares constructor Create(AOwner: TComponent) without override. Components created from a form file are built through the virtual constructor and skip t' +
    'his one.",',
    '      "bad": "type\n  TMyPanel = class(TCustomPanel)\n    constructor Create(AOwner: TComponent);\n  end;",',
    '      "good": "type\n  TMyPanel = class(TCustomPanel)\n    constructor Create(AOwner: TComponent); override;\n  end;"',
    '    },',
    '{',
    '      "id": "component-missing-inherited",',
    '      "name": "Component method without inherited",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "components",',
    '      "description": "An overridden Loaded, CreateParams, CreateWnd, Notification, SetParent, Destroy or Paint of a component does not call inherited, so the VCL skips its own work there. Paint is rep' +
    'orted only if an ancestor''s Paint draws something itself (TCustomPanel, TImage, a grid or a class from the file or index that declares Paint), with medium confidence; TCustomForm and TPaintBox only fi' +
    're OnPaint at run time, so a Paint without inherited is reported there only if the unit uses OnPaint or has a form file; TCustomControl.Paint and TGraphicControl.Paint are empty, so leaving out inheri' +
    'ted there is normal.",',
    '      "bad": "procedure TMyControl.Loaded;\nbegin\n  UpdateLayout;\nend;",',
    '      "good": "procedure TMyControl.Loaded;\nbegin\n  inherited;\n  UpdateLayout;\nend;"',
    '    },',
    '{',
    '      "id": "component-default-mismatch",',
    '      "name": "default does not match constructor",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "components",',
    '      "description": "A property declares a default value, but the constructor sets its field to a different literal. The streaming system does not store values equal to default, so the property is lo' +
    'aded wrongly from the DFM.",',
    '      "bad": "property Size: Integer read FSize write FSize default 5;\n...\nFSize := 10;",',
    '      "good": "property Size: Integer read FSize write FSize default 10;\n...\nFSize := 10;"',
    '    },',
    '{',
    '      "id": "component-missing-free-notification",',
    '      "name": "Component reference without FreeNotification",',
    '      "category": "bug",',
    '      "severity": "warning",',
    '      "group": "components",',
    '      "description": "A component property refers to another component, but its setter does not call FreeNotification. When the other component is freed, a dangling pointer remains. Subcomponents crea' +
    'ted in the constructor are ignored.",',
    '      "bad": "procedure TMyControl.SetLink(const Value: TControl);\nbegin\n  FLink := Value;\nend;",',
    '      "good": "procedure TMyControl.SetLink(const Value: TControl);\nbegin\n  FLink := Value;\n  if Value <> nil then Value.FreeNotification(Self);\nend;"',
    '    },',
    '{',
    '      "id": "component-setter-without-invalidate",',
    '      "name": "Setter without Invalidate",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "components",',
    '      "description": "A property setter changes a field that Paint reads, but does not call Invalidate (or Repaint, Refresh, Changed). The control keeps showing the old state.",',
    '      "bad": "procedure TMyControl.SetColor(const Value: TColor);\nbegin\n  FColor := Value;\nend;",',
    '      "good": "procedure TMyControl.SetColor(const Value: TColor);\nbegin\n  FColor := Value;\n  Invalidate;\nend;"',
    '    },',
    '{',
    '      "id": "component-fixed-pixels",',
    '      "name": "Fixed pixel values",',
    '      "category": "code-smell",',
    '      "severity": "warning",',
    '      "group": "components",',
    '      "description": "Paint or Resize uses fixed pixel values that are too small above 96 dpi. Values passed through ScaleValue or MulDiv or through a method of the class that scales itself (calls Sca' +
    'leValue, MulDiv or a Scale... routine), 0, 1 and -1, and factors of multiplications and divisions are not reported.",',
    '      "bad": "Canvas.FillRect(Rect(0, 0, 16, 16));",',
    '      "good": "Canvas.FillRect(Rect(0, 0, ScaleValue(16), ScaleValue(16)));"',
    '    },',
    '{',
    '      "id": "component-hardcoded-color",',
    '      "name": "Hardcoded color in Paint",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "components",',
    '      "description": "Paint uses an RGB literal, a $00BBGGRR constant or a TColor cast. Such colors ignore VCL styles; system colors like clBtnFace are fine.",',
    '      "bad": "Canvas.Brush.Color := $00FF8000;",',
    '      "good": "Canvas.Brush.Color := StyleServices.GetSystemColor(clHighlight);"',
    '    },',
    '{',
    '      "id": "component-palette-icon",',
    '      "name": "Registered component without palette icon",',
    '      "category": "code-smell",',
    '      "severity": "hint",',
    '      "group": "components",',
    '      "description": "Every class passed to RegisterComponents needs a bitmap named after the class in upper case in a .dcr or .res included with {$R}. From Delphi 11 the sizes 16, 24 and 32 px (NAME1' +
    '6, NAME24, NAME32) are expected as well. Silent when the unit includes no readable resource file.",',
    '      "bad": "{$R *.dcr} // without TMYBUTTON\nRegisterComponents(''Samples'', [TMyButton]);",',
    '      "good": "{$R *.dcr} // with TMYBUTTON16, TMYBUTTON24, TMYBUTTON32\nRegisterComponents(''Samples'', [TMyButton]);"',
    '    }');

implementation

end.
