/*
    Copyright (C) 2004, 2005 Nikolas Zimmermann <wildfox@kde.org>
                  2004, 2005 Rob Buis <buis@kde.org>
                        2006 Alexander Kellett <lypanov@kde.org>

    This file is part of the KDE project

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.

    You should have received a copy of the GNU Library General Public License
    aint with this library; see the file COPYING.LIB.  If not, write to
    the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
    Boston, MA 02111-1307, USA.
*/

#include "config.h"
#include <q3paintdevicemetrics.h>
#include <qpaintdevice.h>

#include <kcanvas/KCanvas.h>
#include <kcanvas/KCanvasPath.h>
#include <kcanvas/KCanvasTypes.h>
#include <kcanvas/device/KRenderingDevice.h>
#include <kcanvas/device/KRenderingFillPainter.h>
#include <kcanvas/device/KRenderingStrokePainter.h>
#include <kcanvas/device/KRenderingPaintServerSolid.h>
#include <kcanvas/device/KRenderingPaintServerGradient.h>
#include <kcanvas/device/KRenderingPaintServer.h>

#include "DocumentImpl.h"
#include <kdom/DOMString.h>
#include <kdom/css/RenderStyle.h>
#include <kdom/css/CSSValueListImpl.h>
#include <kdom/css/CSSPrimitiveValueImpl.h>

#include "ksvg.h"
#include "SVGLengthImpl.h"
#include "SVGStyledElementImpl.h"
#include "KCanvasRenderingStyle.h"
#include "SVGRenderStyle.h"

using namespace KSVG;

bool KSVGPainterFactory::isFilled(const khtml::RenderStyle *style)
{
    SVGPaintImpl *fill = style->svgStyle()->fillPaint();
    if (fill && fill->paintType() == SVG_PAINTTYPE_NONE)
        return false;
    return true;
}

KRenderingPaintServer *KSVGPainterFactory::fillPaintServer(const khtml::RenderStyle *style, const RenderPath* item)
{
    if (!isFilled(style))
        return 0;

    SVGPaintImpl *fill = style->svgStyle()->fillPaint();

    KRenderingPaintServer *fillPaintServer;
    if (!fill) {
        // initial value (black)
        fillPaintServer = QPainter::renderingDevice()->createPaintServer(KCPaintServerType(PS_SOLID));
        KRenderingPaintServerSolid *fillPaintServerSolid = static_cast<KRenderingPaintServerSolid *>(fillPaintServer);
        fillPaintServerSolid->setColor(Qt::black);
    } else if (fill->paintType() == SVG_PAINTTYPE_URI) {
        KDOM::DOMString id(fill->uri());
        fillPaintServer = getPaintServerById(item->document(), id.qstring().mid(1));
        if (item && fillPaintServer)
            fillPaintServer->addClient(item);
    } else {
        fillPaintServer = QPainter::renderingDevice()->createPaintServer(KCPaintServerType(PS_SOLID));
        KRenderingPaintServerSolid *fillPaintServerSolid = static_cast<KRenderingPaintServerSolid *>(fillPaintServer);
        if (fill->paintType() == SVG_PAINTTYPE_CURRENTCOLOR)
            fillPaintServerSolid->setColor(style->color());
        else
            fillPaintServerSolid->setColor(fill->color());
    }

    return fillPaintServer;
}


bool KSVGPainterFactory::isStroked(const khtml::RenderStyle *style)
{
    SVGPaintImpl *stroke = style->svgStyle()->strokePaint();
    if (!stroke || stroke->paintType() == SVG_PAINTTYPE_NONE)
        return false;
    return true;
}

KRenderingPaintServer *KSVGPainterFactory::strokePaintServer(const khtml::RenderStyle *style, const RenderPath* item)
{
    if (!isStroked(style))
        return 0;

    SVGPaintImpl *stroke = style->svgStyle()->strokePaint();

    KRenderingPaintServer *strokePaintServer;
    if (stroke && stroke->paintType() == SVG_PAINTTYPE_URI) {
        KDOM::DOMString id(stroke->uri());
        strokePaintServer = getPaintServerById(item->document(), id.qstring().mid(1));
        if(item && strokePaintServer)
            strokePaintServer->addClient(item);
    } else {
        strokePaintServer = QPainter::renderingDevice()->createPaintServer(KCPaintServerType(PS_SOLID));
        KRenderingPaintServerSolid *strokePaintServerSolid = static_cast<KRenderingPaintServerSolid *>(strokePaintServer);
        if (stroke->paintType() == SVG_PAINTTYPE_CURRENTCOLOR)
            strokePaintServerSolid->setColor(style->color());
        else
            strokePaintServerSolid->setColor(stroke->color());
    }

    return strokePaintServer;
}

double KSVGPainterFactory::cssPrimitiveToLength(const RenderPath *item, KDOM::CSSValueImpl *value, double defaultValue)
{
    KDOM::CSSPrimitiveValueImpl *primitive = static_cast<KDOM::CSSPrimitiveValueImpl *>(value);

    unsigned short cssType = (primitive ? primitive->primitiveType() : (unsigned short) KDOM::CSSPrimitiveValue::CSS_UNKNOWN);
    if(!(cssType > KDOM::CSSPrimitiveValue::CSS_UNKNOWN && cssType <= KDOM::CSSPrimitiveValue::CSS_PC))
        return defaultValue;

    Q3PaintDeviceMetrics *paintDeviceMetrics = 0;

    SVGElementImpl *element = static_cast<SVGElementImpl *>(item->element());
    if(element && element->ownerDocument())
        paintDeviceMetrics = element->ownerDocument()->paintDeviceMetrics();

    if(cssType == KDOM::CSSPrimitiveValue::CSS_PERCENTAGE)
    {
        SVGElementImpl *viewportElement = (element ? element->viewportElement() : 0);
        if(viewportElement)
        {
            double result = primitive->getFloatValue(KDOM::CSSPrimitiveValue::CSS_PERCENTAGE) / 100.0;
            return SVGHelper::PercentageOfViewport(result, viewportElement, LM_OTHER);
        }
    }

    return primitive->computeLengthFloat(const_cast<khtml::RenderStyle *>(item->style()), paintDeviceMetrics);
}

KRenderingStrokePainter KSVGPainterFactory::strokePainter(const khtml::RenderStyle *style, const RenderPath *item)
{
    KRenderingStrokePainter strokePainter;

    strokePainter.setOpacity(style->svgStyle()->strokeOpacity());
    strokePainter.setStrokeWidth(KSVGPainterFactory::cssPrimitiveToLength(item, style->svgStyle()->strokeWidth(), 1.0));

    KDOM::CSSValueListImpl *dashes = style->svgStyle()->strokeDashArray();
    if (dashes) {
        KDOM::CSSPrimitiveValueImpl *dash = 0;
        Q3PaintDeviceMetrics *paintDeviceMetrics = 0;

        SVGElementImpl *element = static_cast<SVGElementImpl *>(item->element());
        if (element && element->ownerDocument())
            paintDeviceMetrics = element->ownerDocument()->paintDeviceMetrics();

        KCDashArray array;
        unsigned long len = dashes->length();
        for (unsigned long i = 0; i < len; i++) {
            dash = static_cast<KDOM::CSSPrimitiveValueImpl *>(dashes->item(i));
            if (dash)
                array.append((float) dash->computeLengthFloat(const_cast<khtml::RenderStyle *>(style), paintDeviceMetrics));
        }

        strokePainter.setDashArray(array);
        strokePainter.setDashOffset(KSVGPainterFactory::cssPrimitiveToLength(item, style->svgStyle()->strokeDashOffset(), 0.0));
    }

    strokePainter.setStrokeMiterLimit(style->svgStyle()->strokeMiterLimit());
    strokePainter.setStrokeCapStyle((KCCapStyle) style->svgStyle()->capStyle());
    strokePainter.setStrokeJoinStyle((KCJoinStyle) style->svgStyle()->joinStyle());

    return strokePainter;
}

KRenderingFillPainter KSVGPainterFactory::fillPainter(const khtml::RenderStyle *style, const RenderPath *item)
{
    KRenderingFillPainter fillPainter;
    
    fillPainter.setFillRule(style->svgStyle()->fillRule() == WR_NONZERO ? RULE_NONZERO : RULE_EVENODD);
    fillPainter.setOpacity(style->svgStyle()->fillOpacity());

    return fillPainter;
}

// vim:ts=4:noet
