package com.github.rami_sabbagh.liko12.graphics.implementation;

import com.badlogic.gdx.graphics.Pixmap;
import com.github.rami_sabbagh.liko12.graphics.exceptions.InvalidColorException;
import com.github.rami_sabbagh.liko12.graphics.exceptions.InvalidCoordinatesException;
import com.github.rami_sabbagh.liko12.graphics.interfaces.Image;
import com.github.rami_sabbagh.liko12.graphics.interfaces.ImageData;
import com.github.rami_sabbagh.liko12.graphics.interfaces.PixelFunction;

import java.nio.ByteBuffer;

import static com.badlogic.gdx.graphics.Pixmap.Blending.None;
import static com.badlogic.gdx.graphics.Pixmap.Format.RGB888;

public class GdxImageData implements ImageData {

    //Implementation note: The Y coordinates are flipped, because the image is being flipped when drawn.

    private final static int MAX_COLORS = 16;
    protected final Pixmap pixmap;
    private final int width;
    private final int height;
    private final ByteBuffer buffer;
    private final GdxFrameBuffer frameBuffer;

    public GdxImageData(GdxFrameBuffer frameBuffer, int width, int height) {
        this(frameBuffer, new Pixmap(width, height, RGB888));
    }

    public GdxImageData(GdxFrameBuffer frameBuffer, Pixmap pixmap) {
        if (pixmap.getFormat() != RGB888)
            throw new UnsupportedOperationException("Unsupported pixmap format: " + pixmap.getFormat().name());

        this.frameBuffer = frameBuffer;
        this.width = pixmap.getWidth();
        this.height = pixmap.getHeight();
        this.pixmap = pixmap;
        this.buffer = this.pixmap.getPixels();

        //Set the blue channel for all the pixels into 1, so the shader can figure those are images pixels.
        for (int i = 2; i < this.width * this.height * 3; i += 3) this.buffer.put(i, (byte) 0xFF);

        this.pixmap.setBlending(None);
    }

    @Override
    public int getWidth() {
        return width;
    }

    @Override
    public int getHeight() {
        return height;
    }

    @Override
    public int getPixel(int x, int y) {
        if (x < 0 || x >= width) throw new InvalidCoordinatesException(x, width, false);
        if (y < 0 || y >= height) throw new InvalidCoordinatesException(y, height, true);

        return buffer.get((x + y * width) * 3);
    }

    @Override
    public void setPixel(int x, int y, int color) {
        if (x < 0 || x >= width) throw new InvalidCoordinatesException(x, width, false);
        if (y < 0 || y >= height) throw new InvalidCoordinatesException(y, height, true);
        if (color < 0 || color >= MAX_COLORS) throw new InvalidColorException(color, MAX_COLORS);

        buffer.put((x + y * width) * 3, (byte) (color / 15.0f * 255.0f));
    }

    @Override
    public void mapPixels(PixelFunction mapper) {
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int index = (x + y * width) * 3;

                int color = mapper.apply(x, y, (int) (buffer.get(index) / 255.0f * 15.0f));
                if (color < 0 || color >= MAX_COLORS) throw new InvalidColorException(color, MAX_COLORS);

                buffer.put(index, (byte) (color / 15.0f * 255.0f));
            }
        }
    }

    @Override
    public void paste(ImageData source, Integer destX, Integer destY, Integer srcX, Integer srcY, Integer srcWidth, Integer srcHeight) {
        if (source == null) throw new NullPointerException("the source imageData is null.");
        if (!(source instanceof GdxImageData))
            throw new UnsupportedOperationException("Unsupported source image type.");
        //NOTE: It's possible to hard-copy the pixels when the instance is not a GdxImageData.

        GdxImageData gdxSource = (GdxImageData) source;

        if (destX == null) destX = 0;
        if (destY == null) destY = 0;
        if (srcX == null) srcX = 0;
        if (srcY == null) srcY = 0;
        if (srcWidth == null) srcWidth = gdxSource.width - srcX;
        if (srcHeight == null) srcHeight = gdxSource.height - srcY;

        pixmap.drawPixmap(gdxSource.pixmap, destX, destY, srcX, srcY, srcWidth, srcHeight);
    }

    @Override
    public Image toImage() {
        return new GdxImage(this.pixmap, this.frameBuffer);
    }

    @Override
    public String export() {
        return null; //TODO: Implement ImageData exporting.
    }

    @Override
    public void dispose() {
        this.pixmap.dispose();
    }
}
