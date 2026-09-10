"""add current uv_index to weather_readings

The `weather_forecasts.uv_index_max` column already here is the day's PEAK
UV. Surfacing it as "UV index" on the current-conditions screen reported
9 ("Very high") at 21:09 in Dharwad, after dark. Current UV is a separate
measurement and needs its own column.

Revision ID: b7e21a4c9d30
Revises: 9464384471a6
Create Date: 2026-09-10 21:40:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'b7e21a4c9d30'
down_revision: Union[str, Sequence[str], None] = '9464384471a6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('weather_readings', sa.Column('uv_index', sa.Float(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('weather_readings', 'uv_index')
