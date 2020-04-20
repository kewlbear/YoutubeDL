.. image:: http://pybee.org/static/images/defaultlogo.png
    :width: 72px
    :target: https://pybee.org/travertino

Travertino
==========

.. image:: https://img.shields.io/pypi/pyversions/travertino.svg
    :target: https://pypi.python.org/pypi/travertino

.. image:: https://img.shields.io/pypi/v/travertino.svg
    :target: https://pypi.python.org/pypi/travertino

.. image:: https://img.shields.io/pypi/status/travertino.svg
    :target: https://pypi.python.org/pypi/travertino

.. image:: https://img.shields.io/pypi/l/travertino.svg
    :target: https://github.com/pybee/travertino/blob/master/LICENSE

.. image:: https://beekeeper.herokuapp.com/projects/pybee/travertino/shield
    :target: https://beekeeper.herokuapp.com/projects/pybee/travertino

.. image:: https://badges.gitter.im/pybee/general.svg
    :target: https://gitter.im/pybee/general

Travertino is a set of constants and utilities for describing user
interfaces, including:

* colors
* directions
* text alignment
* sizes

Usage
-----

Install Travatino:

    $ pip install travertino

Then in your python code, import and use it::

    >>> from travertino import color, rgb,

    # Define a new color as an RGB triple
    >>> red = rgb(0xff, 0x00, 0x00)

    # Parse a color from a string
    >>> color('#dead00')
    rgb(0xde, 0xad, 0x00)

    # Reference a pre-defined color
    >>> color('RebeccaPurple')
    rgb(102, 51, 153)


Community
---------

Travertino is part of the `BeeWare suite`_. You can talk to the community through:

* `@pybeeware on Twitter`_

* The `pybee/general`_ channel on Gitter.

We foster a welcoming and respectful community as described in our
`BeeWare Community Code of Conduct`_.

Contributing
------------

If you experience problems with Travertino, `log them on GitHub`_. If you
want to contribute code, please `fork the code`_ and `submit a pull request`_.

.. _BeeWare suite: http://pybee.org
.. _Read The Docs: https://travertino.readthedocs.io
.. _@pybeeware on Twitter: https://twitter.com/pybeeware
.. _pybee/general: https://gitter.im/pybee/general
.. _BeeWare Community Code of Conduct: http://pybee.org/community/behavior/
.. _log them on Github: https://github.com/pybee/travertino/issues
.. _fork the code: https://github.com/pybee/travertino
.. _submit a pull request: https://github.com/pybee/travertino/pulls


